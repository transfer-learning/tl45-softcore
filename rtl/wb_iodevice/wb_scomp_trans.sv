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
    output reg o_wb_ack;
    output wire o_wb_stall;
    output reg [31:0] o_wb_data;

    output reg o_sc_clk, o_sc_iocyc, o_sc_iowr;
    output reg [7:0] o_sc_ioaddr;
    inout wire [15:0] io_sc_iodata;

    reg [15:0] io_sc_o_data;

    assign io_sc_iodata = o_sc_iowr ? io_sc_o_data:16'hzzzz;

    localparam NUM_WAITS=5;

    localparam
        IDLE=0,
        SC_IO_IN_PROGRESS=1,
        SC_IO_ACK=2,
        SC_IO_END_WAIT=3
        ;

    reg [5:0] current_state;
    reg [5:0] counter;

    wire [7:0] computed_sc_addr;
    assign computed_sc_addr = i_wb_addr[7:0];

    initial begin
        o_wb_data = 0;
        o_sc_iocyc = 0;
        o_sc_iowr = 0;
        o_sc_ioaddr = 0;

        current_state = IDLE;
        counter = 0;
    end

    assign o_wb_stall = current_state != IDLE || counter != 0 || o_sc_clk;
    assign o_wb_ack = current_state == SC_IO_ACK;

    always @(posedge i_clk) begin
        if (i_reset) begin
            o_wb_data <= 0;
            o_sc_iocyc <= 0;
            o_sc_iowr <= 0;
            o_sc_ioaddr <= 0;
            o_sc_clk <= 0;

            current_state <= IDLE;
            counter <= 0;
        end
        else begin
            if (counter == 0) begin
                o_sc_clk <= !o_sc_clk;
            end


            if (current_state == IDLE && !o_sc_clk && counter == 0 && i_wb_stb) begin
                current_state <= SC_IO_IN_PROGRESS;

                o_sc_iocyc <= 1;
                o_sc_iowr <= i_wb_we;
                o_sc_ioaddr <= computed_sc_addr;
                if (i_wb_we)
                    io_sc_o_data <= i_wb_data[15:0];
            end
            else if (current_state == SC_IO_IN_PROGRESS && counter == 0 && !o_sc_clk) begin
                current_state <= SC_IO_ACK;

                if (!o_sc_iowr)
                    o_wb_data <= {16'b0, io_sc_iodata};

                o_sc_iocyc <= 0;
                o_sc_iowr <= 0;
                o_sc_ioaddr <= 0;

            end
            else if (current_state == SC_IO_ACK) begin
                current_state <= SC_IO_END_WAIT;

                o_wb_data <= 0;
            end
            else if (current_state == SC_IO_END_WAIT && counter == 0) begin
                current_state <= IDLE;
            end

            if (counter == 0) begin
                counter <= NUM_WAITS;
            end
            else
                counter <= counter - 1;
        end
    end

`ifdef FORMAL
reg f_past_valid;
initial f_past_valid = 0;

always @(posedge i_clk)
    f_past_valid <= 1;

// Let's keep it reset untill past is valid
always @(*)
    if (!f_past_valid)
        assume(i_reset);

wire [3:0] f_wb_nreqs, f_wb_nacks, f_wb_outstanding;

fwb_slave  #(.DW(32), .AW(30),
        .F_MAX_STALL(10),
        .F_MAX_ACK_DELAY(10),
        .F_OPT_RMW_BUS_OPTION(1),
        .F_OPT_DISCONTINUOUS(1),
        .F_OPT_MINCLOCK_DELAY(1'b0))
    f_wba(i_clk, i_reset,
        i_wb_cyc, i_wb_stb, i_wb_we, i_wb_addr, i_wb_data, i_wb_sel, 
        o_wb_ack, o_wb_stall, o_wb_data, 0,
        f_wb_nreqs, f_wb_nacks, f_wb_outstanding);

`endif


endmodule