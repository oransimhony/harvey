`default_nettype none

parameter integer MEMORY_SIZE = 'h3000;

module proc(
    input clk, reset
    , input [7:0] memory [0:MEMORY_SIZE] 
    , output reg [31:0] out
    , output reg ready
    , output reg [31:0] address
    , output reg write_enable
    , output reg [2:0] write_size
);
parameter SHOULD_DUMP = 0;
parameter MAX_INFINITE_LOOP = 5;

reg [31:0] regfile[0:32];
reg [31:0] csrs[0:'h1000];
reg [31:0] instruction, imm_i, imm_u, imm_s, imm_j, imm_b, res, addr, pc, npc;
reg [11:0] csr;
reg [6:0] opcode, funct7;
reg [4:0] rs1, rs2, rd;
reg [2:0] funct3;
reg should_writeback = 0, should_end = 0, should_access_memory = 0, is_store = 0, cond = 0, test_finished = 0, test_passed = 0;
reg [7:0] same_pc = 0;

/* OPCODES */
parameter [6:0] OP_IMM = 7'b0010011;
parameter [6:0] OP = 7'b0110011;
parameter [6:0] JAL = 7'b1101111;
parameter [6:0] JALR = 7'b1100111;
parameter [6:0] AUIPC = 7'b0010111;
parameter [6:0] LUI = 7'b0110111;
parameter [6:0] LOAD = 7'b0000011;
parameter [6:0] STORE = 7'b0100011;
parameter [6:0] BRANCH = 7'b1100011;
parameter [6:0] SYSTEM = 7'b1110011;
parameter [6:0] MISC_MEM = 7'b0001111;

/* OP_IMM FUNCT3 */
parameter [2:0] ADDI = 3'b000;
parameter [2:0] SLTI = 3'b010;
parameter [2:0] SLTIU = 3'b011;
parameter [2:0] XORI = 3'b100;
parameter [2:0] ORI = 3'b110;
parameter [2:0] ANDI = 3'b111;
parameter [2:0] SLLI = 3'b001;
parameter [2:0] SRLI = 3'b101;

/* OP FUNCT3 */
parameter [2:0] ADD = 3'b000;
parameter [2:0] SLT = 3'b010;
parameter [2:0] SLTU = 3'b011;
parameter [2:0] XOR = 3'b100;
parameter [2:0] OR = 3'b110;
parameter [2:0] AND = 3'b111;
parameter [2:0] SLL = 3'b001;
parameter [2:0] SRL = 3'b101;

/* BRANCH FUNCT3 */
parameter [2:0] BEQ = 3'b000;
parameter [2:0] BNE = 3'b001;
parameter [2:0] BLT = 3'b100;
parameter [2:0] BGE = 3'b101;
parameter [2:0] BLTU = 3'b110;
parameter [2:0] BGEU = 3'b111;

/* SYSTEM FUNCT3 */
parameter [2:0] PRIV = 3'b000;
parameter [2:0] CSRRW = 3'b001;
parameter [2:0] CSRRS = 3'b010;
parameter [2:0] CSRRC = 3'b011;
parameter [2:0] CSRRWI = 3'b101;
parameter [2:0] CSRRSI = 3'b110;
parameter [2:0] CSRRCI = 3'b111;

/* LOAD FUNCT3 */
parameter [2:0] LB = 3'b000;
parameter [2:0] LH = 3'b001;
parameter [2:0] LW = 3'b010;
parameter [2:0] LBU = 3'b100;
parameter [2:0] LHU = 3'b101;

/* STORE FUNCT3 */
parameter [2:0] SB = 3'b000;
parameter [2:0] SH = 3'b001;
parameter [2:0] SW = 3'b010;


/* PRIV IMM */
parameter [11:0] ECALL = 'b0;
parameter [11:0] EBREAK = 'b1;
parameter [11:0] SRET = 'b100000010;
parameter [11:0] MRET = 'b1100000010;
parameter [11:0] MNRET = 'b11100000010;

/* MISM_MEM FUNCT3 */
parameter [2:0] FENCE = 3'b000;
parameter [2:0] FENCE_I = 3'b001;

/* CSRS */
parameter [11:0] CSR_mhartid = 'hF14;
parameter [11:0] CSR_mstatus = 'h300;
parameter [11:0] CSR_mepc = 'h341;

always @(posedge clk, posedge reset) begin
    if (reset) begin
        pc <= 0;
        ready <= 0;
        for (int i = 0; i < 64; i = i + 1) begin
            regfile[i] <= 32'h0;
        end

        for (int i = 0; i < $size(csrs); i = i + 1) begin
            csrs[i] <= 32'h0;
        end
    end else begin
        ready <= 1;

        // Instruction Fetch
        instruction = {memory[pc], memory[pc + 1]
                      , memory[pc + 2], memory[pc + 3]};
        $display("INSTRUCTION: %h", instruction);

        // Instruction Decode
        opcode = instruction[6:0];
        rd = instruction[11:7];
        funct3 = instruction[14:12];
        rs1 = instruction[19:15];
        rs2 = instruction[24:20];
        funct7 = instruction[31:25];
        imm_i = {{20{instruction[31]}}, instruction[31:20]};
        csr = instruction[31:20];
        imm_u = { instruction[31:12], 12'b0};
        imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
        imm_j = {{12{instruction[31]}}, instruction[19:12], instruction[20]
                , instruction[30:21], 1'b0};
        imm_b = {{20{instruction[31]}}, instruction[7], instruction[30:25]
                , instruction[11:8], 1'b0};
        npc = pc + 4;
        should_access_memory = 0;
        should_writeback = 0;
        cond = 0;
        write_enable = 0;

        case (opcode)
            OP_IMM: begin
                case (funct3)
                    ADDI: res = regfile[rs1] + imm_i;
                    SLTI: res = $signed(regfile[rs1]) < $signed(imm_i);
                    SLTIU: res = (regfile[rs1] < imm_i) ? 1 : 0;
                    SLLI: res = regfile[rs1] << rs2;
                    SRLI: begin
                        if (imm_i[11:5] == 7'b0) begin
                            /* SRLI */
                            res = regfile[rs1] >> rs2;
                        end else if (imm_i[11:5] == 7'b0100000) begin
                            /* SRAI */
                            res = $signed(regfile[rs1]) >>> rs2;
                        end else begin
                            $display("Illegal Instruction");
                        end
                    end
                    ORI: res = regfile[rs1] | imm_i;
                    XORI: res = regfile[rs1] ^ imm_i;
                    ANDI: res = regfile[rs1] & imm_i;
                    default: begin
                        $display("Unknown OP_IMM rs1=%d funct3=%b imm=%h", rs1
                                , funct3, imm_i);
                        $finish;
                    end
                endcase
                $display("OP_IMM rd=%d rs1=%d funct3=%b imm=%h => %h", rd, rs1
                        , funct3, imm_i, res);
                should_writeback = 1;
            end
            OP: begin
                case (funct3)
                    ADD: begin
                        if (funct7 == 0) begin
                            res = regfile[rs1] + regfile[rs2];
                        end else if (funct7 == 7'b0100000) begin
                            res = regfile[rs1] - regfile[rs2];
                            $display("SUB %d - %d = %d, %d, %d", regfile[rs1]
                                    , regfile[rs2], res, rs1, rs2);
                        end else begin
                            $display("Illegal Instruction");
                            $finish;
                        end
                    end
                    SLT: res = $signed(regfile[rs1]) < $signed(regfile[rs2]);
                    SLTU: res = (regfile[rs1] < regfile[rs2]) ? 1 : 0;
                    SLL: res = regfile[rs1] << regfile[rs2][4:0];
                    SRL: begin
                        if (funct7 == 7'b0) begin
                            /* SRL */
                            res = regfile[rs1] >> regfile[rs2][4:0];
                        end else if (funct7 == 7'b0100000) begin
                            /* SRA */
                            res = $signed(regfile[rs1]) >>> regfile[rs2][4:0];
                        end else begin
                            $display("Illegal Instruction");
                            $finish;
                        end
                    end
                    OR: res = regfile[rs1] | regfile[rs2];
                    XOR: res = regfile[rs1] ^ regfile[rs2];
                    AND: res = regfile[rs1] & regfile[rs2];
                    default: begin
                        $display("Unknown OP rs1=%d rs2=%d funct3=%b funct7=%b"
                                , rs1, rs2, funct3, funct7);
                        $finish;
                    end
                endcase
                should_writeback = 1;
            end
            JAL: begin
                addr = pc + imm_j;
                $display("JAL rd=%d addr=%h", rd, addr);
                npc = addr;
                res = pc + 4;
                should_writeback = 1;
            end
            JALR: begin
                res = regfile[rs1] + imm_i;
                addr = {res[31:1], 1'b0};
                $display("JALR rd=%d rs1=%d imm=%h => %h", rd, rs1, imm_i
                        , addr);
                npc = addr;
                res = pc + 4;
                should_writeback = 1;
                // RET
                if (rd == 0 && rs1 == 1 && imm_i == 0) begin
                    $display("RET");
                end else begin
                end
            end
            LUI: begin
                $display("LUI rd=%d imm=%h", rd, imm_u[31:12]);
                res = imm_u;
                should_writeback = 1;
            end
            AUIPC: begin
                $display("AUIPC rd=%d imm=%h", rd, imm_u[31:12]);
                res = pc + imm_u;
                should_writeback = 1;
            end
            LOAD: begin
                $display("LOAD rd=%02d rs1=%02d imm=%h funct3=%b", rd, rs1
                        , imm_i, funct3);
                addr = regfile[rs1] + imm_i;
                $display("MEM addr=%h %02h %02h %02h %02h", addr
                        , memory[addr + 0], memory[addr + 1]
                        , memory[addr + 2], memory[addr + 3]);
                case (funct3)
                    LB: res = {{24{memory[addr][7]}}, memory[addr]};
                    LBU: res = {24'b0, memory[addr]};
                    LH: res = {{16{memory[addr + 1][7]}}, memory[addr + 1]
                            , memory[addr + 0]};
                    LHU: res = {16'b0, memory[addr + 1], memory[addr + 0]};
                    LW: res = {memory[addr + 3], memory[addr + 2]
                            , memory [addr + 1], memory[addr + 0]};
                    default: begin
                        $display("Unsupported LOAD size funct3=%b", funct3);
                        $finish;
                    end
                endcase
                should_writeback = 1;
            end
            STORE: begin
                $display("STORE rs1=%02d rs2=%02d imm=%h funct3=%b", rs1, rs2
                        , imm_s, funct3);
                addr = regfile[rs1] + imm_s;
                res = regfile[rs2];
                is_store = 1;
                should_access_memory = 1;
                write_size = funct3;
            end
            BRANCH: begin
                $display("BRANCH rs1=%02d rs2=%02d funct3=%b", rs1, rs2
                        , funct3);
                case (funct3)
                    BEQ: cond = regfile[rs1] == regfile[rs2];
                    BNE: cond = regfile[rs1] != regfile[rs2];
                    BLT: cond = $signed(regfile[rs1]) < $signed(regfile[rs2]);
                    BGE: cond = $signed(regfile[rs1]) >= $signed(regfile[rs2]);
                    BLTU: cond = regfile[rs1] < regfile[rs2];
                    BGEU: cond = regfile[rs1] >= regfile[rs2];
                    default: begin
                        $display("Unknown BRANCH %b", funct3);
                        $finish;
                    end
                endcase

                if (cond) begin
                    npc = pc + imm_b;
                end

                // Halt
                if (pc == npc) begin
                    $display("HALT DETECTED %d", same_pc);
                end
            end
            SYSTEM: begin
                case (funct3)
                    PRIV: begin
                        case (imm_i)
                            ECALL: begin
                                $display("ECALL %d", regfile[3]);
                                if (regfile[3] > 1) begin
                                    $display("Failure in test %d"
                                            , (regfile[3] - 1) >> 1);
                                    test_passed = 0;
                                    test_finished = 1;
                                end else if (regfile[3] == 1) begin
                                    $display("TEST PASSED");
                                    test_passed = 1;
                                    test_finished = 1;
                                end
                            end
                            EBREAK: begin
                                $display("EBREAK");
                                $finish;
                            end
                            MRET: begin
                                $display("MRET");
                                npc = csrs[CSR_mepc];
                            end
                            default: begin
                                $display("Invalid SYSTEM PRIV %b", imm_i);
                                $finish;
                            end
                        endcase
                    end
                    CSRRW: begin
                        $display("CSRRW rd=%02d rs1=%02d csr=%h", rd, rs1, csr);
                        if (rd != 0) begin
                            res = csrs[csr];
                            should_writeback = 1;
                        end
                        csrs[csr] = regfile[rs1];
                    end
                    CSRRWI: begin
                        $display("CSRRWI rd=%02d imm=%02d csr=%h", rd, rs1
                                , csr);
                        if (rd != 0) begin
                            res = csrs[csr];
                            should_writeback = 1;
                        end
                        csrs[csr] = {27'b0, rs1};
                    end
                    CSRRS: begin
                        $display("CSRRS rd=%02d rs1=%02d csr=%h", rd, rs1, csr);
                        if (rs1 != 0) begin
                            $display("Unsupported");
                            $finish;
                        end

                        // mhartid
                        if (csr == CSR_mhartid) begin
                            res = 0; /* mhartid hardcoded to 0 */
                            should_writeback = 1;
                        end else begin
                            $display("Unsupported CSR");
                            $finish;
                        end
                    end
                    default: begin
                        $display(
                            "Unknown SYSTEM rd=%02d rs1=%02d imm=%h funct3=%b"
                            , rd, rs1, imm_i, funct3);
                        $finish;
                    end
                endcase
            end
            MISC_MEM: begin
                case (funct3)
                    FENCE: begin
                        $display("FENCE ignored");
                    end
                    FENCE_I: begin
                        $display("FENCE.I ignored");
                    end
                    default: begin
                        $display(
                            "Unknown MISC_MEM rd=%02d rs1=%02d imm=%h funct3=%b"
                            , rd, rs1, imm_i, funct3);
                        $finish;
                    end
                endcase
            end
            default: begin
                if (!$isunknown(opcode)) begin
                    $display("OPCODE: %b", opcode);
                    $finish;
                end else $finish;
            end
        endcase

        /* Memory access */
        if (should_access_memory) begin
            if (is_store) begin
                out = res;
                address = addr;
                write_enable = 1;
                case (write_size)
                    3'b0: $display("*%h = %h", address, out[7:0]);
                    3'b1: $display("*%h = %h", address, out[15:0]);
                    default: $display("*%h = %h", address, out);
                endcase
            end
        end

        /* Writeback */
        if (should_writeback && rd != 0) begin
            regfile[rd] = res;
        end


        /* Registers dump */
        if (SHOULD_DUMP) begin
            for (int i = 0; i < 32; i = i + 1) begin
                $write("x%02d = %h ", i, regfile[i]);
                if (i % 4 == 3) $display("");
            end
            $display("PC = %h\tNPC = %h\tsame_pc = %d", pc, npc, same_pc);
        end else $display("PC = %h", pc);

        if (pc == npc) begin
            same_pc = same_pc + 1;
        end else begin
            same_pc = 0;
        end
        if (pc < 0 || pc > $size(memory) || should_end == 1
            || same_pc >= MAX_INFINITE_LOOP || test_finished == 1) begin
            ready <= 0;
            $finish;
        end else begin
            pc <= npc;
        end
    end
end
endmodule

module driver;

reg clk, reset, ready, write_enable;
reg [31:0] number, address;
reg [7:0] memory [0:MEMORY_SIZE];
reg [2:0] write_size;

initial begin
    $readmemh("memory_contents.hex", memory);
end

proc p(clk, reset, memory, number, ready, address, write_enable, write_size);

initial begin
    clk = 0;
    reset = 1;
    #10 reset = 0;
end

always #5 clk = ~clk;

always @(posedge clk) begin
    if (ready) begin
        if (write_enable == 1 && !$isunknown(address)
            && !$isunknown(number)) begin
            case (write_size)
                3'b000: memory[address] = number[7:0];
                3'b001: begin
                    memory[address + 0] = number[7:0];
                    memory[address + 1] = number[15:8];  
                end
                3'b010: begin
                    memory[address + 0] = number[7:0];
                    memory[address + 1] = number[15:8];
                    memory[address + 2] = number[23:16];
                    memory[address + 3] = number[31:24];
                end
                default: begin
                    $display("Unsupported WRITE size %b", write_size);
                    $finish;
                end
            endcase
            $display("MEM_S %02h %02h %02h %02h %h %b"
            , memory[address + 0], memory[address + 1]
            , memory[address + 2], memory[address + 3]
            , number, write_size);
        end
    end
end
endmodule
