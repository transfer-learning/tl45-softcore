module wb_scomp_trans(
    i_clk, i_reset,
    i_wb_cyc, i_wb_stb, i_wb_we,
    i_wb_addr, i_wb_data, i_wb_sel,
    o_wb_ack, o_wb_stall,
    o_wb_data,

    o_sc_clk,
    o_sc_iocyc,
    o_sc_iowr,
    o_sc_ioaddr,
    io_sc_iodata
);
    input wire i_clk, i_reset, i_wb_cyc, i_wb_stb, i_wb_we;
    input wire [29:0] i_wb_addr;
    input wire [31:0] i_wb_data;
    input wire [3:0] i_wb_sel;
    output wire o_wb_ack;
    output wire o_wb_stall;
    output reg [31:0] o_wb_data;

    output reg o_sc_clk, o_sc_iocyc, o_sc_iowr;
    output reg [7:0] o_sc_ioaddr;
    inout wire [15:0] io_sc_iodata;

    `ifdef FORMAL
    parameter SCOMP_CLK_DIV_FACTOR = 1;
    `else
    localparam SCOMP_CLK_DIV_FACTOR = 2;
    `endif
// Wishbone Initial
    initial begin
        o_wb_data = 0;
    end

    reg [15:0] scomp_clk_divider;
    initial scomp_clk_divider = 0;

// Scomp Initial
    reg [15:0] o_sc_data;
    wire [15:0] i_sc_data;
    reg sc_io_wr_int;
    initial begin
        o_sc_data = 0;
        o_sc_clk = 0;
        o_sc_iocyc = 0;
        o_sc_iowr = 0;
        sc_io_wr_int = 0;
        o_sc_ioaddr = 0;
    end

    assign i_sc_data = io_sc_iodata;
    assign io_sc_iodata = sc_io_wr_int ? o_sc_data : 16'hzzzz;

    localparam IDLE = 0,
               SCOMP_IO_WRITE = 1,
               SCOMP_IO_WRITE_2 = 2,
               SCOMP_IO_READ_PREP = 3,
               SCOMP_IO_READ=4,
               SCOMP_IO_ACK = 5;
    reg [15:0] current_state;
    initial current_state = IDLE;


    assign o_wb_stall = current_state != IDLE || !i_wb_cyc;
    assign o_wb_ack = (current_state == SCOMP_IO_ACK) && (i_wb_cyc);
// Wishbone State Machine
    always @(posedge i_clk) begin
        if (i_reset || !i_wb_cyc) begin
            current_state <= IDLE;
            o_sc_iocyc <= 0;
            o_sc_iowr <= 0;
            o_sc_ioaddr <= 0;
        end else if (current_state == IDLE && i_wb_cyc && i_wb_stb) begin
            o_sc_ioaddr <= i_wb_addr[7:0];
            if (i_wb_we) begin
                current_state <= SCOMP_IO_WRITE;
                o_sc_data <= i_wb_data[15:0];
            end else
                current_state <= SCOMP_IO_READ_PREP;
        end else if (current_state == SCOMP_IO_WRITE && scomp_clk_divider == SCOMP_CLK_DIV_FACTOR && !o_sc_clk) begin
            // IO Write && Clk about to rise
            o_sc_iocyc <= 1;
            o_sc_iowr <= 1;
            current_state <= SCOMP_IO_WRITE_2;
        end else if (current_state == SCOMP_IO_WRITE_2 && scomp_clk_divider == SCOMP_CLK_DIV_FACTOR && !o_sc_clk) begin
            o_sc_iocyc <= 0;
            o_sc_iowr <= 0;
            current_state <= SCOMP_IO_ACK;
        end else if (current_state == SCOMP_IO_READ_PREP && scomp_clk_divider == SCOMP_CLK_DIV_FACTOR && !o_sc_clk) begin
            current_state <= SCOMP_IO_READ;
            o_sc_iocyc <= 1;
        end else if (current_state == SCOMP_IO_READ && scomp_clk_divider == SCOMP_CLK_DIV_FACTOR && !o_sc_clk) begin
            o_wb_data <= {16'h0, i_sc_data};
            current_state <= SCOMP_IO_ACK;
            o_sc_iocyc <= 0;
        end else if (current_state == SCOMP_IO_ACK) begin // Guarentee one ack cycle
            o_sc_iocyc <= 0;
            o_sc_iowr <= 0;
            current_state <= IDLE;
        end
    end

// SCOMP State Machine
    always @(posedge i_clk) begin
        if (i_reset) begin
            scomp_clk_divider <= 0;
            o_sc_clk <= 0;
        end else
            if (scomp_clk_divider >= SCOMP_CLK_DIV_FACTOR) begin
                o_sc_clk <= !o_sc_clk;
                scomp_clk_divider <= 0;
            end else
                scomp_clk_divider <= scomp_clk_divider + 1;
    end

// SCOMP Outputs
    always @(*) begin
        sc_io_wr_int = current_state == SCOMP_IO_WRITE || current_state == SCOMP_IO_WRITE_2; // SCOMP IOWrite
    end
    
`ifdef FORMAL
reg f_past_valid;
initial f_past_valid = 0;
initial assume(current_state == IDLE);

always @(posedge i_clk)
    f_past_valid <= 1;

always @(*) begin
    assert(current_state <= SCOMP_IO_ACK);
    assert(scomp_clk_divider <= SCOMP_CLK_DIV_FACTOR);
end

// Let's keep it reset untill past is valid
always @(*)
    if (!f_past_valid)
        assume(i_reset);

wire [3:0] f_wb_nreqs, f_wb_nacks, f_wb_outstanding;

fwb_slave  #(.DW(32), .AW(30),
        .F_MAX_STALL(25),
        .F_MAX_ACK_DELAY(25),
        .F_OPT_RMW_BUS_OPTION(0),
        .F_OPT_DISCONTINUOUS(0),
        .F_OPT_MINCLOCK_DELAY(1'b0))
    f_wba(i_clk, i_reset,
        i_wb_cyc, i_wb_stb, i_wb_we, i_wb_addr, i_wb_data, i_wb_sel, 
        o_wb_ack, o_wb_stall, o_wb_data, 0,
        f_wb_nreqs, f_wb_nacks, f_wb_outstanding);

`endif


endmodule