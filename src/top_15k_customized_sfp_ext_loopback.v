// =============================================================================
// 15K Customized PHY External SFP Loopback Test Top
// -----------------------------------------------------------------------------
// Target:
//   GW5AT-15 / Q0 Lane0 / Customized PHY / external SFP TX->RX optical loopback
//
// Expected IP config:
//   q0.ln0 enable                 = true
//   tx_data_rate / rx_data_rate    = 1.25G
//   width_mode                     = 8
//   encode_mode / decode_mode      = OFF
//   word_align_enable              = false
//   loopBack                       = OFF     // external SFP loopback, not internal loopback
//   rx_pol_invert                  = true    // fixes SFP RX P/N swap on the board
//
// Existing source dependency:
//   prbs7_single_channel.v, prbs7_gen.v, prbs7_chk.v
//
// Board connection:
//   SFP TX optical output -> LC loopback / fiber -> SFP RX optical input
//
// LED:
//   led = PRBS7 lock. 1 means external SFP loopback path is receiving valid PRBS7.
//
// ILA/GAO:
//   Add signals with prefix ila15cphy_*.
// =============================================================================

module top
(
    input  wire clk,     // 50 MHz board clock, kept for compatibility / slow heartbeat
    input  wire rst_n,   // low-active board reset
    output wire led
);

localparam [31:0] TOP_VERSION = 32'h15C0_0001;
localparam integer PRBS_WIDTH = 8;

// -----------------------------------------------------------------------------
// Customized PHY Q0 Lane0 interface wires
// -----------------------------------------------------------------------------
wire        cphy_rx_pcs_clk;
wire [87:0] cphy_rx_data;
wire [4:0]  cphy_rx_fifo_rdusewd;
wire        cphy_rx_fifo_aempty;
wire        cphy_rx_fifo_empty;
wire        cphy_rx_valid;

wire        cphy_tx_pcs_clk;
wire [4:0]  cphy_tx_fifo_wrusewd;
wire        cphy_tx_fifo_afull;
wire        cphy_tx_fifo_full;

wire        cphy_refclk;
wire        cphy_signal_detect;
wire        cphy_rx_cdr_lock;
wire        cphy_pll_lock;
wire        cphy_ready;

wire        cphy_rx_clk_i;
wire        cphy_rx_fifo_rden_i;
wire        cphy_tx_clk_i;
wire [79:0] cphy_tx_data_i;
wire        cphy_tx_fifo_wren_i;
wire        cphy_pma_rstn_i;
wire        cphy_pcs_rx_rst_i;
wire        cphy_pcs_tx_rst_i;

assign cphy_rx_clk_i = cphy_rx_pcs_clk;
assign cphy_tx_clk_i = cphy_tx_pcs_clk;

// PMA reset is active low by port naming; PCS resets are active high.
// Keep this simple to avoid reset-FSM deadlocks during first bring-up.
assign cphy_pma_rstn_i  = rst_n;
assign cphy_pcs_rx_rst_i = ~rst_n;
assign cphy_pcs_tx_rst_i = ~rst_n;

// Read RX FIFO whenever it is not almost empty and the RX side is usable.
assign cphy_rx_fifo_rden_i = rst_n & cphy_ready & cphy_rx_cdr_lock & ~cphy_rx_fifo_aempty;

// -----------------------------------------------------------------------------
// Instantiate generated SerDes Customized PHY
// -----------------------------------------------------------------------------
SerDes_Top u_SerDes_Top
(
    .Customized_PHY_Top_q0_ln0_rx_pcs_clkout_o   (cphy_rx_pcs_clk),
    .Customized_PHY_Top_q0_ln0_rx_data_o         (cphy_rx_data),
    .Customized_PHY_Top_q0_ln0_rx_fifo_rdusewd_o (cphy_rx_fifo_rdusewd),
    .Customized_PHY_Top_q0_ln0_rx_fifo_aempty_o  (cphy_rx_fifo_aempty),
    .Customized_PHY_Top_q0_ln0_rx_fifo_empty_o   (cphy_rx_fifo_empty),
    .Customized_PHY_Top_q0_ln0_rx_valid_o        (cphy_rx_valid),

    .Customized_PHY_Top_q0_ln0_tx_pcs_clkout_o   (cphy_tx_pcs_clk),
    .Customized_PHY_Top_q0_ln0_tx_fifo_wrusewd_o (cphy_tx_fifo_wrusewd),
    .Customized_PHY_Top_q0_ln0_tx_fifo_afull_o   (cphy_tx_fifo_afull),
    .Customized_PHY_Top_q0_ln0_tx_fifo_full_o    (cphy_tx_fifo_full),

    .Customized_PHY_Top_q0_ln0_refclk_o          (cphy_refclk),
    .Customized_PHY_Top_q0_ln0_signal_detect_o   (cphy_signal_detect),
    .Customized_PHY_Top_q0_ln0_rx_cdr_lock_o     (cphy_rx_cdr_lock),
    .Customized_PHY_Top_q0_ln0_pll_lock_o        (cphy_pll_lock),
    .Customized_PHY_Top_q0_ln0_ready_o           (cphy_ready),

    .Customized_PHY_Top_q0_ln0_rx_clk_i          (cphy_rx_clk_i),
    .Customized_PHY_Top_q0_ln0_rx_fifo_rden_i    (cphy_rx_fifo_rden_i),
    .Customized_PHY_Top_q0_ln0_tx_clk_i          (cphy_tx_clk_i),
    .Customized_PHY_Top_q0_ln0_tx_data_i         (cphy_tx_data_i),
    .Customized_PHY_Top_q0_ln0_tx_fifo_wren_i    (cphy_tx_fifo_wren_i),
    .Customized_PHY_Top_q0_ln0_pma_rstn_i        (cphy_pma_rstn_i),
    .Customized_PHY_Top_q0_ln0_pcs_rx_rst_i      (cphy_pcs_rx_rst_i),
    .Customized_PHY_Top_q0_ln0_pcs_tx_rst_i      (cphy_pcs_tx_rst_i)
);

// -----------------------------------------------------------------------------
// TX/RX domain reset stretching for PRBS logic only
// -----------------------------------------------------------------------------
reg [7:0] tx_rstn_sr;
reg [7:0] rx_rstn_sr;

always @(posedge cphy_tx_pcs_clk or negedge rst_n) begin
    if (!rst_n)
        tx_rstn_sr <= 8'h00;
    else if (cphy_pll_lock && cphy_ready)
        tx_rstn_sr <= {tx_rstn_sr[6:0], 1'b1};
    else
        tx_rstn_sr <= 8'h00;
end

always @(posedge cphy_rx_pcs_clk or negedge rst_n) begin
    if (!rst_n)
        rx_rstn_sr <= 8'h00;
    else if (cphy_ready && cphy_signal_detect && cphy_rx_cdr_lock)
        rx_rstn_sr <= {rx_rstn_sr[6:0], 1'b1};
    else
        rx_rstn_sr <= 8'h00;
end

wire tx_prbs_rstn = tx_rstn_sr[7];
wire rx_prbs_rstn = rx_rstn_sr[7];

// -----------------------------------------------------------------------------
// PRBS7 generator/checker
// -----------------------------------------------------------------------------
wire [PRBS_WIDTH-1:0] prbs_tx_data;
wire [PRBS_WIDTH-1:0] prbs_rx_data;
wire                  prbs_lock;

assign cphy_tx_fifo_wren_i = tx_prbs_rstn & ~cphy_tx_fifo_afull;

// For 8-bit raw Customized PHY, follow Gowin reference style:
// put the 8-bit payload into the low byte of the low 10-bit slot; keep others 0.
assign cphy_tx_data_i = {70'd0, 2'b00, prbs_tx_data};
assign prbs_rx_data   = cphy_rx_data[7:0];

prbs7_single_channel #(
    .WIDTH(PRBS_WIDTH)
) u_prbs7_single_channel (
    // TX PRBS generator
    .tx_clk_i  (cphy_tx_pcs_clk),
    .tx_rstn_i (tx_prbs_rstn),
    .tx_en_i   (cphy_tx_fifo_wren_i),
    .tx_data_o (prbs_tx_data),

    // RX PRBS checker
    .rx_clk_i  (cphy_rx_pcs_clk),
    .rx_rstn_i (rx_prbs_rstn),
    .rx_en_i   (cphy_rx_valid),
    .rx_data_i (prbs_rx_data),
    .lock_o    (prbs_lock)
);

assign led = prbs_lock;

// -----------------------------------------------------------------------------
// Debug counters / sticky flags
// -----------------------------------------------------------------------------
reg [31:0] tx_wr_cnt;
reg [31:0] rx_valid_cnt;
reg [31:0] rx_read_cnt;
reg [31:0] rx_data_change_cnt;
reg [7:0]  rx_last_byte;
reg        prbs_lock_seen;
reg        rx_valid_seen;
reg        cdr_lock_seen;
reg        ready_seen;
reg        signal_detect_seen;
reg        tx_afull_seen;
reg        tx_full_seen;
reg        rx_empty_seen;
reg        rx_aempty_seen;
reg        rx_activity_toggle;

always @(posedge cphy_tx_pcs_clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_wr_cnt     <= 32'd0;
        tx_afull_seen <= 1'b0;
        tx_full_seen  <= 1'b0;
    end else begin
        if (cphy_tx_fifo_wren_i)
            tx_wr_cnt <= tx_wr_cnt + 32'd1;
        if (cphy_tx_fifo_afull)
            tx_afull_seen <= 1'b1;
        if (cphy_tx_fifo_full)
            tx_full_seen <= 1'b1;
    end
end

always @(posedge cphy_rx_pcs_clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_valid_cnt       <= 32'd0;
        rx_read_cnt        <= 32'd0;
        rx_data_change_cnt <= 32'd0;
        rx_last_byte       <= 8'd0;
        prbs_lock_seen     <= 1'b0;
        rx_valid_seen      <= 1'b0;
        cdr_lock_seen      <= 1'b0;
        ready_seen         <= 1'b0;
        signal_detect_seen <= 1'b0;
        rx_empty_seen      <= 1'b0;
        rx_aempty_seen     <= 1'b0;
        rx_activity_toggle <= 1'b0;
    end else begin
        if (cphy_rx_fifo_rden_i)
            rx_read_cnt <= rx_read_cnt + 32'd1;

        if (cphy_rx_valid) begin
            rx_valid_cnt  <= rx_valid_cnt + 32'd1;
            rx_valid_seen <= 1'b1;
            rx_activity_toggle <= ~rx_activity_toggle;

            if (prbs_rx_data != rx_last_byte) begin
                rx_data_change_cnt <= rx_data_change_cnt + 32'd1;
                rx_last_byte       <= prbs_rx_data;
            end
        end

        if (prbs_lock)
            prbs_lock_seen <= 1'b1;
        if (cphy_rx_cdr_lock)
            cdr_lock_seen <= 1'b1;
        if (cphy_ready)
            ready_seen <= 1'b1;
        if (cphy_signal_detect)
            signal_detect_seen <= 1'b1;
        if (cphy_rx_fifo_empty)
            rx_empty_seen <= 1'b1;
        if (cphy_rx_fifo_aempty)
            rx_aempty_seen <= 1'b1;
    end
end

// Slow heartbeat in board-clock domain, useful if you choose to probe it.
reg [25:0] hb_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        hb_cnt <= 26'd0;
    else
        hb_cnt <= hb_cnt + 26'd1;
end

// -----------------------------------------------------------------------------
// GAO/ILA probe wires. Search prefix: ila15cphy_
// -----------------------------------------------------------------------------
(* keep = "true" *) wire [31:0] ila15cphy_top_version;
(* keep = "true" *) wire        ila15cphy_clk_heartbeat;
(* keep = "true" *) wire        ila15cphy_pll_lock;
(* keep = "true" *) wire        ila15cphy_ready;
(* keep = "true" *) wire        ila15cphy_signal_detect;
(* keep = "true" *) wire        ila15cphy_rx_cdr_lock;
(* keep = "true" *) wire        ila15cphy_rx_valid;
(* keep = "true" *) wire [87:0] ila15cphy_rx_data;
(* keep = "true" *) wire [7:0]  ila15cphy_rx_byte;
(* keep = "true" *) wire        ila15cphy_rx_fifo_rden;
(* keep = "true" *) wire [4:0]  ila15cphy_rx_fifo_rdusewd;
(* keep = "true" *) wire        ila15cphy_rx_fifo_aempty;
(* keep = "true" *) wire        ila15cphy_rx_fifo_empty;
(* keep = "true" *) wire        ila15cphy_tx_fifo_wren;
(* keep = "true" *) wire [79:0] ila15cphy_tx_data;
(* keep = "true" *) wire [7:0]  ila15cphy_tx_byte;
(* keep = "true" *) wire [4:0]  ila15cphy_tx_fifo_wrusewd;
(* keep = "true" *) wire        ila15cphy_tx_fifo_afull;
(* keep = "true" *) wire        ila15cphy_tx_fifo_full;
(* keep = "true" *) wire        ila15cphy_tx_prbs_rstn;
(* keep = "true" *) wire        ila15cphy_rx_prbs_rstn;
(* keep = "true" *) wire        ila15cphy_prbs_lock;
(* keep = "true" *) wire        ila15cphy_prbs_lock_seen;
(* keep = "true" *) wire        ila15cphy_rx_valid_seen;
(* keep = "true" *) wire        ila15cphy_cdr_lock_seen;
(* keep = "true" *) wire        ila15cphy_ready_seen;
(* keep = "true" *) wire        ila15cphy_signal_detect_seen;
(* keep = "true" *) wire [31:0] ila15cphy_tx_wr_cnt;
(* keep = "true" *) wire [31:0] ila15cphy_rx_valid_cnt;
(* keep = "true" *) wire [31:0] ila15cphy_rx_read_cnt;
(* keep = "true" *) wire [31:0] ila15cphy_rx_data_change_cnt;
(* keep = "true" *) wire [7:0]  ila15cphy_rx_last_byte;
(* keep = "true" *) wire        ila15cphy_tx_afull_seen;
(* keep = "true" *) wire        ila15cphy_tx_full_seen;
(* keep = "true" *) wire        ila15cphy_rx_empty_seen;
(* keep = "true" *) wire        ila15cphy_rx_aempty_seen;
(* keep = "true" *) wire        ila15cphy_rx_activity_toggle;

assign ila15cphy_top_version        = TOP_VERSION;
assign ila15cphy_clk_heartbeat      = hb_cnt[25];
assign ila15cphy_pll_lock           = cphy_pll_lock;
assign ila15cphy_ready              = cphy_ready;
assign ila15cphy_signal_detect      = cphy_signal_detect;
assign ila15cphy_rx_cdr_lock        = cphy_rx_cdr_lock;
assign ila15cphy_rx_valid           = cphy_rx_valid;
assign ila15cphy_rx_data            = cphy_rx_data;
assign ila15cphy_rx_byte            = prbs_rx_data;
assign ila15cphy_rx_fifo_rden       = cphy_rx_fifo_rden_i;
assign ila15cphy_rx_fifo_rdusewd    = cphy_rx_fifo_rdusewd;
assign ila15cphy_rx_fifo_aempty     = cphy_rx_fifo_aempty;
assign ila15cphy_rx_fifo_empty      = cphy_rx_fifo_empty;
assign ila15cphy_tx_fifo_wren       = cphy_tx_fifo_wren_i;
assign ila15cphy_tx_data            = cphy_tx_data_i;
assign ila15cphy_tx_byte            = prbs_tx_data;
assign ila15cphy_tx_fifo_wrusewd    = cphy_tx_fifo_wrusewd;
assign ila15cphy_tx_fifo_afull      = cphy_tx_fifo_afull;
assign ila15cphy_tx_fifo_full       = cphy_tx_fifo_full;
assign ila15cphy_tx_prbs_rstn       = tx_prbs_rstn;
assign ila15cphy_rx_prbs_rstn       = rx_prbs_rstn;
assign ila15cphy_prbs_lock          = prbs_lock;
assign ila15cphy_prbs_lock_seen     = prbs_lock_seen;
assign ila15cphy_rx_valid_seen      = rx_valid_seen;
assign ila15cphy_cdr_lock_seen      = cdr_lock_seen;
assign ila15cphy_ready_seen         = ready_seen;
assign ila15cphy_signal_detect_seen = signal_detect_seen;
assign ila15cphy_tx_wr_cnt          = tx_wr_cnt;
assign ila15cphy_rx_valid_cnt       = rx_valid_cnt;
assign ila15cphy_rx_read_cnt        = rx_read_cnt;
assign ila15cphy_rx_data_change_cnt = rx_data_change_cnt;
assign ila15cphy_rx_last_byte       = rx_last_byte;
assign ila15cphy_tx_afull_seen      = tx_afull_seen;
assign ila15cphy_tx_full_seen       = tx_full_seen;
assign ila15cphy_rx_empty_seen      = rx_empty_seen;
assign ila15cphy_rx_aempty_seen     = rx_aempty_seen;
assign ila15cphy_rx_activity_toggle = rx_activity_toggle;

endmodule
