`timescale 1ns / 1ps

module Simulador;

    //Sinais do simulador
    reg clock;
    reg reset;
    
    //Memória
    reg [31:0] MBR_in;
    wire [31:0] MBR_out;
    wire [31:0] MAR;
    wire mem_enable;
    wire mem_op; // 0=Ler, 1=Escrever
    
    //I/O
    reg [31:0] input_data;
    wire [31:0] output_data;

    //RAM
    reg [31:0] RAM [0:1023];

    //Instanciação do Processador
    Processador cpu (
        .clock(clock), 
        .reset(reset), 
        .MBR_in(MBR_in), 
        .MBR_out(MBR_out), 
        .MAR(MAR), 
        .mem_enable(mem_enable), 
        .mem_op(mem_op), 
        .input_data(input_data), 
        .output_data(output_data)
    );

    //Geração de Clock
    initial begin
        clock = 0;
        forever #5 clock = ~clock; // Clock de 10ns (100MHz)
    end

    // TABELA DE OPCODES
    localparam OP_ADD       = 6'd1;
    localparam OP_SUB       = 6'd2;
    localparam OP_JE        = 6'd8;
    localparam OP_JLE       = 6'd13;
    localparam OP_JMP       = 6'd14;
    localparam OP_LOAD      = 6'd15; //Mem -> Reg
    localparam OP_STORE     = 6'd16; //Reg -> Mem
    localparam OP_LDCTH     = 6'd17; //Load Const High
    localparam OP_LDCTL     = 6'd18; //Load Const Low
    localparam OP_LDEXT     = 6'd19; //Input -> Reg
    localparam OP_STEXT     = 6'd20; //Reg -> Output

    //Tarefa para facilitar e tornar intuitiva a escrita das instruções
    //Opcode(6) | R_Dest(5) | R_Src1(5) | R_Src2(5) | Imm_Low(11)
    // O campo 'Imm' de 16 bits engloba R_Src2 nos bits superiores.
    task load_inst;
        input [31:0] addr;      //Endereço na RAM
        input [5:0] opcode;     //Opcode
        input [4:0] r_dest;     //Registrador Destino
        input [4:0] r_src1;     //Registrador Fonte 1
        input [4:0] r_src2;     //Registrador Fonte 2 (Se não usar, ponha 0)
        input [15:0] imm_val;   //Valor Imediato (Se instrução usa src2, cuidado com overlap)
        
        reg [15:0] final_imm;
        begin
            //Se for uma instrução que usa Src2 (ADD, SUB, LOAD, STORE),
            //precisa garantir que Src2 esteja nos bits [15:11] do campo imediato.
            //Se for JMP ou LDC, usa o imm_val direto.
            
            if (opcode >= 1 && opcode <= 7) begin // ULA
                 final_imm = {r_src2, 11'd0}; 
            end else if (opcode == OP_LOAD) begin
                 //LOAD: MAR <= rf_rdata2. Então o ponteiro é o Src2.
                 final_imm = {r_src2, 11'd0};
            end else if (opcode == OP_STORE) begin
                 //STORE: MBR_out <= rf_rdata2. O dado é Src2. O ponteiro é Src1.
                 final_imm = {r_src2, 11'd0};
            end else begin
                 //Para Jumps, LDC, etc, usa-se o valor imediato direto
                 final_imm = imm_val;
            end

            //Escreve na RAM
            RAM[addr] = {opcode, r_dest, r_src1, final_imm};
        end
    endtask

    //Lógica de Memória Simulada
    always @(posedge clock) begin
        if (mem_enable) begin
            if (mem_op == 0) begin // LEITURA
                MBR_in <= RAM[MAR];
            end else begin // ESCRITA
                RAM[MAR] <= MBR_out;
            end
        end
    end

    //Bloco de Teste
    integer i;
    initial begin
        //Inicialização
        reset = 1;
        MBR_in = 0;
        input_data = 40; // <--- ENTRADA DO USUÁRIO (Teste > 25)
        
        //Limpa memória
        for (i=0; i<1024; i=i+1) RAM[i] = 0;

        //Carregamento do Programa (Endereços 0 a 18)
      
        
        //DADOS
        RAM[1] = 32'd5;   // Dado A
        RAM[2] = 32'd20;  // Dado B

        //CÓDIGO
        
        //0: JMP +3
        //processador faz PC <= PC + imm. 0 + 3 = 3.
        load_inst(0, OP_JMP, 0, 0, 0, 16'd3);

        //3: LDCTH R0, 0
        load_inst(3, OP_LDCTH, 5'd0, 5'd0, 0, 16'd0);

        //4: LDCTL R0, 1
        load_inst(4, OP_LDCTL, 5'd0, 5'd0, 0, 16'd1);

        //5: LOAD R1, R0
        load_inst(5, OP_LOAD, 5'd1, 5'd0, 5'd0, 16'd0);

        //6: LDCTL R0, 2
        load_inst(6, OP_LDCTL, 5'd0, 5'd0, 0, 16'd2);

        //7: LOAD R2, R0
        load_inst(7, OP_LOAD, 5'd2, 5'd0, 5'd0, 16'd0);

        //8: LDEXT R3
        load_inst(8, OP_LDEXT, 5'd3, 5'd0, 0, 16'd0);

        //9: ADD R5, R1, R2
        load_inst(9, OP_ADD, 5'd5, 5'd1, 5'd2, 16'd0);

        //10: SUB R4, R3, R5
        load_inst(10, OP_SUB, 5'd4, 5'd3, 5'd5, 16'd0);

        //11: JLE +4
        load_inst(11, OP_JLE, 5'd0, 5'd0, 0, 16'd4);

        //Se maior que 25
        
        //12: STORE R0, R5
        load_inst(12, OP_STORE, 5'd0, 5'd0, 5'd5, 16'd0);

        //13: STEXT R0
        load_inst(13, OP_STEXT, 5'd0, 5'd0, 0, 16'd0);

        //14: JMP +4
        load_inst(14, OP_JMP, 5'd0, 5'd0, 0, 16'd4);

        //Se menor ou igual
        
        //15: LDCTL R0, 1
        load_inst(15, OP_LDCTL, 5'd0, 5'd0, 0, 16'd1);

        //16: STORE R0, R4
        load_inst(16, OP_STORE, 5'd0, 5'd0, 5'd4, 16'd0);

        //17: STEXT R0
        load_inst(17, OP_STEXT, 5'd0, 5'd0, 0, 16'd0);

        //18: JMP 0 (Loop Infinito)
        load_inst(18, OP_JMP, 5'd0, 5'd0, 0, 16'd0);


        //Execução

        $display("______Inicio da Simulacao (Input = %3d)___________________________", input_data);
        #20 reset = 0; //Solta o reset

        //Tempo suficiente para executar todas as instruções
        #800; 
        
        $display("______Fim da Simulacao__________________________");
        $finish;
    end

    //Monitoramento

    always @(posedge clock) begin
        if (!reset) begin
             $display("PC:%2d |fase:%2d |R0:%3d |R1:%3d | R2:%3d | R3:%3d | R4:%3d | R5:%3d | M1:%2d | M2:%3d| output:%3d", 
                      cpu.PC, cpu.fase+1, $signed(cpu.regs.REGS[0]) ,$signed(cpu.regs.REGS[1]), 
                      $signed(cpu.regs.REGS[2]), $signed(cpu.regs.REGS[3]), $signed(cpu.regs.REGS[4]), 
                      $signed(cpu.regs.REGS[5]), $signed(RAM[1]), RAM[2], output_data);
        end
    end

initial begin
    //Cria o arquivo que o GTKWave vai ler
    $dumpfile("ondas.vcd");
    
    //Grava todas as variáveis do módulo atual (0 significa "todos os níveis abaixo")
    $dumpvars(0, Simulador);
end

endmodule