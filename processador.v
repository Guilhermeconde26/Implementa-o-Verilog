/*  
    0	0       NOP	    -
    1	00001	ADD	    ULA
    2	00010	SUB	    ULA
    3	00011   MUL	    ULA
    4	00100	DIV	    ULA
    5	00101	AND	    ULA
    6	00110	OR	    ULA
    7	00111	NOT	    ULA
    8	01000	JE	    Jump
    9	01001	JNE	    Jump
    10	01010	JG	    Jump
    11	01011	JL	    Jump
    12	01100	JGE	    Jump
    13	01101	JLE	    Jump
    14	01110	JMP	    Jump
    15	01111	LOAD	Mem
    16	10000	STORE	Mem
    17	10001	LDCTH	Immed
    18	10010	LDCTL	Immed
    19	10011	LDEXT	I/O
    20	10100	STEXT	I/O 
*/



module Processador(

    input wire clock,
    input wire reset,
    //Memórias
    input wire [31:0] MBR_in,
    output reg [31:0] MBR_out,
    output reg [31:0] MAR,
    output reg mem_enable,
    output reg mem_op, // 0=Ler, 1=Escrever
    //I/O
    input wire [31:0] input_data,
    output reg [31:0] output_data
);

    //Definição das Fases
    localparam FASE_FETCH   = 3'd0; // Busca
    localparam FASE_DECODE  = 3'd1; // Decodificação
    localparam FASE_EXECUTE = 3'd2; // Execução / Cálculo Endereço
    localparam FASE_MEM     = 3'd3; // Acesso à Memória
    localparam FASE_WB      = 3'd4; // Escrita no Registrador

    //Registradores Internos
    reg [2:0] fase;
    reg [31:0] PC;
    reg [31:0] IR;
    
    //Flags
    reg flag_z, flag_n; 

    //Decodificação
    wire [5:0] opcode = IR[31:26];
    wire [4:0] r_dest = IR[25:21];
    wire [4:0] r_src1 = IR[20:16];
    wire [4:0] r_src2 = IR[15:11];
    wire [15:0] imm16 = IR[15:0];
    
    //Extensão de sinal e formatação de imediatos
    wire [31:0] s_imm = {{16{imm16[15]}}, imm16};
    wire [31:0] imm_high = {imm16, 16'd0}; // Para LoadCteH
    wire [31:0] imm_low  = {16'd0, imm16}; // Para LoadCteL

    //Interconexão
    //Sinais para o Banco de Registradores
    reg rf_we;
    reg [31:0] rf_wdata;
    wire [31:0] rf_rdata1, rf_rdata2;

    //Sinais para a ULA
    reg [31:0] alu_op1, alu_op2;
    wire [31:0] alu_res;
    wire alu_z_wire, alu_n_wire;

    //Instâncias
    BRegistradores regs (
        .clock(clock), .reset(reset), .write_enable(rf_we),
        .r_addr1(r_src1), .r_addr2(r_src2),
        .w_addr(r_dest), .w_data(rf_wdata),
        .r_data1(rf_rdata1), .r_data2(rf_rdata2)
    );

    ULA ula (
        .a(alu_op1), .b(alu_op2),
        .opcode(opcode),
        .result(alu_res), .resultf(rf_wdata),
        .zero(alu_z_wire), .neg(alu_n_wire)
    );

    //Fases
    always @(negedge clock or negedge reset) begin
        if (reset) begin
            fase <= FASE_FETCH;
            PC <= 0;
            mem_enable <= 0;
            output_data <= 0;
            flag_z <= 0;
            flag_n <= 0;
            rf_we <= 0;
        end else begin
            rf_we <= 0; 

            case (fase)
                FASE_FETCH: begin
                    MAR <= PC;
                    mem_op <= 0;
                    mem_enable <= 1;
                    fase <= FASE_DECODE;
                end

                FASE_DECODE: begin
                    mem_enable <= 0;
                    IR <= MBR_in;
                    fase <= FASE_EXECUTE;
                end

                FASE_EXECUTE: begin
                    // Preparação dos Operandos da ULA
                    alu_op1 <= rf_rdata1;
                    case (opcode)
                        6'd17: alu_op2 <= imm_high;     //LDCTH
                        6'd18: alu_op2 <= imm_low;      //LDCTL
                        6'd19: alu_op2 <= input_data;   //LDEXT
                        default: alu_op2 <= rf_rdata2;  //(ADD, SUB, LOAD, STORE...)
                    endcase

                    //Desvios
                    if (opcode >= 6'd8 && opcode <= 6'd14) begin
                        case (opcode)
                            6'd8:  if (alu_z_wire) PC <= PC + s_imm; else PC <= PC + 1; // JE
                            6'd9:  if (!alu_z_wire) PC <= PC + s_imm; else PC <= PC + 1; // JNE
                            6'd10: if (!alu_n_wire && !alu_z_wire) PC <= PC + s_imm; else PC <= PC + 1; // JG
                            6'd11: if (alu_n_wire) PC <= PC + s_imm; else PC <= PC + 1; // JL
                            6'd12: if (!alu_n_wire || alu_z_wire) PC <= PC + s_imm; else PC <= PC + 1; // JGE
                            6'd13: if (alu_n_wire || alu_z_wire) PC <= PC + s_imm; else PC <= PC + 1; // JLE
                            6'd14: PC <= PC + s_imm; // JMP
                        endcase
                        fase <= FASE_FETCH; 
                    end
                    
                    //Store
                    else if (opcode == 6'd16) begin
                        MAR <= rf_rdata1;   
                        MBR_out <= rf_rdata2; 
                        mem_op <= 1;          
                        mem_enable <= 1;
                        fase <= FASE_MEM;
                    end
                    
                    //Store Externo
                    else if (opcode == 6'd20) begin //STOREEXT
                        output_data <= rf_rdata1;
                        PC <= PC + 1;
                        fase <= FASE_FETCH;
                    end

                    //Load
                    else if (opcode == 6'd15) begin 
                        MAR <= rf_rdata2;
                        mem_op <= 0; 
                        mem_enable <= 1;
                        fase <= FASE_MEM;
                    end

                    else if (opcode >= 6'd1 && opcode <= 6'd7) begin
                        //flag_z <= alu_z_wire; 
                        //flag_n <= alu_n_wire;
                        fase <= FASE_WB;
                    end

                    else begin
                        // Salva as flags geradas pela ULA
                        fase <= FASE_WB;
                    end
                end

                FASE_MEM: begin
                    mem_enable <= 0;
                    
                    if (opcode == 6'd16) begin
                        PC <= PC + 1;
                        fase <= FASE_FETCH;
                    end else begin
                        fase <= FASE_WB;
                    end
                end

                FASE_WB: begin
                    rf_we <= 1;
                    
                    if (opcode == 6'd15)
                        rf_wdata <= MBR_in;
                    else //Resultado da ULA
                        rf_wdata <= alu_res;

                    PC <= PC + 1; //Incrementa PC para próxima instrução
                    fase <= FASE_FETCH;
                end

            endcase
        end
    end


endmodule




module BRegistradores(
    
    input wire clock,
    input wire reset,
    input wire write_enable,
    input wire [4:0] r_addr1,  //Endereço Leitura 1
    input wire [4:0] r_addr2,  //Endereço Leitura 2
    input wire [4:0] w_addr,   //Endereço Escrita
    input wire [31:0] w_data,  //Dado a ser escrito
    output wire [31:0] r_data1,
    output wire [31:0] r_data2
);

    reg [31:0] REGS [0:31];
    integer i;

    //Leitura (assíncrona)
    assign r_data1 = REGS[r_addr1];
    assign r_data2 = REGS[r_addr2];

    //Escrita (síncrona)
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                REGS[i] <= 32'd0;
        end else if (write_enable) begin
            REGS[w_addr] <= w_data;
        end
    end

endmodule



module ULA(
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [5:0] opcode,
    output reg [31:0] result,
    input wire [31:0] resultf,
    output wire zero,
    output wire neg
);

    //Definição local de alguns opcodes para uso na ula (deveria ter feito pra tudo no início ):
    localparam OP_ADD       = 6'd1;
    localparam OP_SUB       = 6'd2;
    localparam OP_MUL       = 6'd3;
    localparam OP_DIV       = 6'd4;
    localparam OP_AND       = 6'd5;
    localparam OP_OR        = 6'd6;
    localparam OP_NOT       = 6'd7;
    localparam OP_LOAD      = 6'd15; //pass-through
    localparam OP_LOADCTEH  = 6'd17;
    localparam OP_LOADCTEL  = 6'd18;
    localparam OP_LOADEXT   = 6'd19; //pass-through

    always @(*) begin
        case (opcode)
            OP_ADD: result = a + b;
            OP_SUB: result = a - b;
            OP_MUL: result = a * b;
            OP_DIV: result = (b != 0) ? (a / b) : 32'd0;
            OP_AND: result = a & b;
            OP_OR:  result = a | b;
            OP_NOT: result = ~b; 
            
            // Tratamento de Imediatos
            // Assumindo que 'a' contém o valor atual do registrador e 'b' contém o imediato shiftado
            OP_LOADCTEH: result = (a & 32'h0000FFFF) | b; 
            OP_LOADCTEL: result = (a & 32'hFFFF0000) | b;
            
            //Pass-through (Input data entra como 'b')
            OP_LOADEXT: result = b; 
            OP_LOAD: result = b;
            
            default: result = 32'd0;
        endcase
    end

    //Flags
    assign zero = (resultf == 32'd0);
    assign neg  = resultf[31];

endmodule



