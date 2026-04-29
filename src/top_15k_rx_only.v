`timescale 1 ns / 1 ps

// =============================================================================
// GW138K -> GW15K cross-board 8B10B verification
// Role : 15K RX checker only
// Mode : RoraLink 8B10B Framing mode, 32-bit user data, 1 lane
// IP   : RX-only Simplex + BackChannel Timer + CRC
// =============================================================================
module top
(
    input  clk,      // 50 MHz
    input  rst_n,    // low-active
    output led
);

`define LANE_WIDTH       1
`define LANE_DATA_WIDTH  32

parameter DATA_WIDTH      = `LANE_DATA_WIDTH * `LANE_WIDTH;
parameter STRB_WIDTH      = DATA_WIDTH / 8;
parameter LANE_WIDTH      = `LANE_WIDTH;
parameter LANE_DATA_WIDTH = `LANE_DATA_WIDTH;
parameter FRAME_BEATS     = 16;

localparam [31:0] TOP_VERSION   = 32'h1502_0001;
localparam [15:0] PASS_FRAME_TH = 16'd8;

// Must match the 138K TX top.
localparam [31:0] TX_PATTERN0 = 32'h12_34_56_78;
localparam [31:0] TX_PATTERN1 = 32'h9A_BC_DE_F0;
localparam [31:0] TX_PATTERN2 = 32'h55_AA_C3_3C;
localparam [31:0] TX_PATTERN3 = 32'h0F_1E_2D_3C;

// -----------------------------------------------------------------------------
// RX user interface from RoraLink 8B10B IP
// -----------------------------------------------------------------------------
wire [DATA_WIDTH-1:0] user_rx_data  /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_rx_strb  /* synthesis syn_keep=1 */;
wire                  user_rx_valid /* synthesis syn_keep=1 */;
wire                  user_rx_last  /* synthesis syn_keep=1 */;

wire crc_pass_fail_n;
wire crc_valid;
wire hard_err;
wire soft_err;
wire frame_err;
wire channel_up                  /* synthesis syn_keep=1 */;
wire [LANE_WIDTH-1:0] lane_up    /* synthesis syn_keep=1 */;

// -----------------------------------------------------------------------------
// Clock / reset / SerDes status
// -----------------------------------------------------------------------------
wire sys_clk                     /* synthesis syn_keep=1 */;
wire sys_rst;
wire cfg_clk;
wire cfg_pll_lock;
wire sys_reset_gen;
wire gt_reset;
wire gt_pcs_rx_reset;
wire [LANE_WIDTH-1:0] gt_pcs_rx_clk;
wire gt_pll_ok;
wire [LANE_WIDTH-1:0] gt_rx_align_link;
wire [LANE_WIDTH-1:0] gt_rx_pma_lock;
wire [LANE_WIDTH-1:0] gt_rx_k_lock;
wire link_reset;
wire sys_reset;

assign sys_clk = gt_pcs_rx_clk[0];

// Do not use software-controlled GT resets in this bring-up top.
assign gt_reset        = 1'b0;
assign gt_pcs_rx_reset = 1'b0;

assign sys_reset_gen = cfg_pll_lock & gt_pll_ok & rst_n;

// -----------------------------------------------------------------------------
// RX checker state
// First received user_rx_last is used as frame boundary acquisition. After that,
// the next valid beat must be pattern0, then pattern1/2/3..., last on beat 15.
// -----------------------------------------------------------------------------
reg        channel_up_1d;
reg        rx_aligned;
reg [7:0]  rx_beat_cnt;
reg [31:0] rx_last_data;
reg [31:0] rx_expected_d;
reg [31:0] rx_first_bad_data;
reg [31:0] rx_first_bad_expected;
reg [7:0]  rx_first_bad_beat;
reg [31:0] rx_valid_cnt;
reg [31:0] rx_frame_cnt;
reg [15:0] rx_good_frame_cnt;
reg        rx_seen_valid;
reg        rx_seen_last;
reg        rx_activity_toggle;
reg        payload_err_seen;
reg        last_err_seen;
reg        hard_err_seen;
reg        soft_err_seen;
reg        frame_err_seen;
reg        crc_err_seen;
reg        test_pass;

wire [31:0] rx_expected_word;
wire        rx_payload_mismatch;
wire        rx_last_expected;
wire        rx_last_mismatch;
wire        rx_frame_good_now;
wire        any_err_seen;
wire        any_err_now;

// 15K has only one LED in this project:
// led = 1 means 15K RX got channel_up and passed pattern/last/CRC checking.
assign led = test_pass;

// -----------------------------------------------------------------------------
// PLL and reset generator
// Keep using the 15K PLL port list from your current project.
// reset_gen is already present as src/reset_gen.v in the 15K repository.
// -----------------------------------------------------------------------------
Gowin_PLL u_Gowin_PLL
(
    .reset   (!rst_n),
    .lock    (cfg_pll_lock),
    .clkout0 (cfg_clk),
    .mdclk   (clk),
    .clkin   (clk)
);

reset_gen u_sys_reset_gen
(
    .i_clk1 (sys_clk),
    .i_lock (sys_reset_gen),
    .o_rst1 (sys_rst)
);

// -----------------------------------------------------------------------------
// RX checker
// -----------------------------------------------------------------------------
function [31:0] f_rx_pattern;
    input [1:0] sel;
    begin
        case (sel)
            2'd0: f_rx_pattern = TX_PATTERN0;
            2'd1: f_rx_pattern = TX_PATTERN1;
            2'd2: f_rx_pattern = TX_PATTERN2;
            2'd3: f_rx_pattern = TX_PATTERN3;
            default: f_rx_pattern = TX_PATTERN0;
        endcase
    end
endfunction

assign rx_expected_word    = f_rx_pattern(rx_beat_cnt[1:0]);
assign rx_last_expected    = (rx_beat_cnt == FRAME_BEATS-1);
assign rx_payload_mismatch = rx_aligned & user_rx_valid & (user_rx_data != rx_expected_word);
assign rx_last_mismatch    = rx_aligned & user_rx_valid & (user_rx_last != rx_last_expected);
assign rx_frame_good_now   = rx_aligned & user_rx_valid & user_rx_last & rx_last_expected &
                             !rx_payload_mismatch & !rx_last_mismatch;
assign any_err_seen        = payload_err_seen | last_err_seen | hard_err_seen |
                             soft_err_seen | frame_err_seen | crc_err_seen;
assign any_err_now         = hard_err | soft_err | frame_err |
                             (crc_valid & !crc_pass_fail_n) |
                             rx_payload_mismatch | rx_last_mismatch;

always @(posedge sys_clk) begin
    if (sys_rst) begin
        channel_up_1d         <= 1'b0;
        rx_aligned            <= 1'b0;
        rx_beat_cnt           <= 8'd0;
        rx_last_data          <= 32'd0;
        rx_expected_d         <= 32'd0;
        rx_first_bad_data     <= 32'd0;
        rx_first_bad_expected <= 32'd0;
        rx_first_bad_beat     <= 8'd0;
        rx_valid_cnt          <= 32'd0;
        rx_frame_cnt          <= 32'd0;
        rx_good_frame_cnt     <= 16'd0;
        rx_seen_valid         <= 1'b0;
        rx_seen_last          <= 1'b0;
        rx_activity_toggle    <= 1'b0;
        payload_err_seen      <= 1'b0;
        last_err_seen         <= 1'b0;
        hard_err_seen         <= 1'b0;
        soft_err_seen         <= 1'b0;
        frame_err_seen        <= 1'b0;
        crc_err_seen          <= 1'b0;
        test_pass             <= 1'b0;
    end else begin
        channel_up_1d <= channel_up;

        if (!channel_up_1d) begin
            rx_aligned            <= 1'b0;
            rx_beat_cnt           <= 8'd0;
            rx_last_data          <= 32'd0;
            rx_expected_d         <= 32'd0;
            rx_first_bad_data     <= 32'd0;
            rx_first_bad_expected <= 32'd0;
            rx_first_bad_beat     <= 8'd0;
            rx_valid_cnt          <= 32'd0;
            rx_frame_cnt          <= 32'd0;
            rx_good_frame_cnt     <= 16'd0;
            rx_seen_valid         <= 1'b0;
            rx_seen_last          <= 1'b0;
            rx_activity_toggle    <= 1'b0;
            payload_err_seen      <= 1'b0;
            last_err_seen         <= 1'b0;
            hard_err_seen         <= 1'b0;
            soft_err_seen         <= 1'b0;
            frame_err_seen        <= 1'b0;
            crc_err_seen          <= 1'b0;
            test_pass             <= 1'b0;
        end else begin
            if (hard_err) hard_err_seen <= 1'b1;
            if (soft_err) soft_err_seen <= 1'b1;
            if (frame_err) frame_err_seen <= 1'b1;
            if (crc_valid && !crc_pass_fail_n) crc_err_seen <= 1'b1;

            if (user_rx_valid) begin
                rx_seen_valid      <= 1'b1;
                rx_valid_cnt       <= rx_valid_cnt + 32'd1;
                rx_activity_toggle <= ~rx_activity_toggle;
                rx_last_data       <= user_rx_data;
                rx_expected_d      <= rx_expected_word;

                if (user_rx_last)
                    rx_seen_last <= 1'b1;

                if (!rx_aligned) begin
                    if (user_rx_last) begin
                        rx_aligned   <= 1'b1;
                        rx_beat_cnt  <= 8'd0;
                        rx_frame_cnt <= rx_frame_cnt + 32'd1;
                    end
                end else begin
                    if (rx_payload_mismatch) begin
                        payload_err_seen <= 1'b1;
                        if (!payload_err_seen) begin
                            rx_first_bad_data     <= user_rx_data;
                            rx_first_bad_expected <= rx_expected_word;
                            rx_first_bad_beat     <= rx_beat_cnt;
                        end
                    end

                    if (rx_last_mismatch)
                        last_err_seen <= 1'b1;

                    if (rx_payload_mismatch || rx_last_mismatch) begin
                        rx_good_frame_cnt <= 16'd0;
                    end else if (rx_frame_good_now) begin
                        if (rx_good_frame_cnt != 16'hffff)
                            rx_good_frame_cnt <= rx_good_frame_cnt + 16'd1;
                    end

                    if (user_rx_last) begin
                        rx_beat_cnt  <= 8'd0;
                        rx_frame_cnt <= rx_frame_cnt + 32'd1;
                    end else if (rx_beat_cnt == FRAME_BEATS-1) begin
                        rx_beat_cnt <= 8'd0;
                    end else begin
                        rx_beat_cnt <= rx_beat_cnt + 8'd1;
                    end
                end
            end

            if (any_err_seen || any_err_now)
                test_pass <= 1'b0;
            else if (rx_good_frame_cnt >= PASS_FRAME_TH)
                test_pass <= 1'b1;
        end
    end
end

// -----------------------------------------------------------------------------
// ILA signals, search prefix: ila15rx_
// Recommended ILA clock: sys_clk / gt_pcs_rx_clk[0]
// Recommended trigger  : ila15rx_user_rx_valid == 1, or ila15rx_any_err_now == 1
// -----------------------------------------------------------------------------
wire [31:0] ila15rx_top_version          /* synthesis syn_keep=1 */ = TOP_VERSION;
wire        ila15rx_cfg_pll_lock         /* synthesis syn_keep=1 */ = cfg_pll_lock;
wire        ila15rx_gt_pll_ok            /* synthesis syn_keep=1 */ = gt_pll_ok;
wire        ila15rx_sys_rst              /* synthesis syn_keep=1 */ = sys_rst;
wire        ila15rx_sys_reset            /* synthesis syn_keep=1 */ = sys_reset;
wire        ila15rx_link_reset           /* synthesis syn_keep=1 */ = link_reset;
wire        ila15rx_channel_up           /* synthesis syn_keep=1 */ = channel_up;
wire        ila15rx_channel_up_1d        /* synthesis syn_keep=1 */ = channel_up_1d;
wire [0:0]  ila15rx_lane_up              /* synthesis syn_keep=1 */ = lane_up;
wire [0:0]  ila15rx_gt_rx_pma_lock       /* synthesis syn_keep=1 */ = gt_rx_pma_lock;
wire [0:0]  ila15rx_gt_rx_k_lock         /* synthesis syn_keep=1 */ = gt_rx_k_lock;
wire [0:0]  ila15rx_gt_rx_align_link     /* synthesis syn_keep=1 */ = gt_rx_align_link;
wire [31:0] ila15rx_user_rx_data         /* synthesis syn_keep=1 */ = user_rx_data;
wire [3:0]  ila15rx_user_rx_strb         /* synthesis syn_keep=1 */ = user_rx_strb;
wire        ila15rx_user_rx_valid        /* synthesis syn_keep=1 */ = user_rx_valid;
wire        ila15rx_user_rx_last         /* synthesis syn_keep=1 */ = user_rx_last;
wire [7:0]  ila15rx_rx_beat_cnt          /* synthesis syn_keep=1 */ = rx_beat_cnt;
wire [31:0] ila15rx_rx_expected_word     /* synthesis syn_keep=1 */ = rx_expected_word;
wire [31:0] ila15rx_rx_last_data         /* synthesis syn_keep=1 */ = rx_last_data;
wire [31:0] ila15rx_rx_expected_d        /* synthesis syn_keep=1 */ = rx_expected_d;
wire        ila15rx_rx_aligned           /* synthesis syn_keep=1 */ = rx_aligned;
wire        ila15rx_rx_payload_mismatch  /* synthesis syn_keep=1 */ = rx_payload_mismatch;
wire        ila15rx_rx_last_expected     /* synthesis syn_keep=1 */ = rx_last_expected;
wire        ila15rx_rx_last_mismatch     /* synthesis syn_keep=1 */ = rx_last_mismatch;
wire [31:0] ila15rx_rx_first_bad_data    /* synthesis syn_keep=1 */ = rx_first_bad_data;
wire [31:0] ila15rx_rx_first_bad_expecte /* synthesis syn_keep=1 */ = rx_first_bad_expected;
wire [7:0]  ila15rx_rx_first_bad_beat    /* synthesis syn_keep=1 */ = rx_first_bad_beat;
wire [31:0] ila15rx_rx_valid_cnt         /* synthesis syn_keep=1 */ = rx_valid_cnt;
wire [31:0] ila15rx_rx_frame_cnt         /* synthesis syn_keep=1 */ = rx_frame_cnt;
wire [15:0] ila15rx_rx_good_frame_cnt    /* synthesis syn_keep=1 */ = rx_good_frame_cnt;
wire        ila15rx_rx_seen_valid        /* synthesis syn_keep=1 */ = rx_seen_valid;
wire        ila15rx_rx_seen_last         /* synthesis syn_keep=1 */ = rx_seen_last;
wire        ila15rx_rx_activity_toggle   /* synthesis syn_keep=1 */ = rx_activity_toggle;
wire        ila15rx_crc_valid            /* synthesis syn_keep=1 */ = crc_valid;
wire        ila15rx_crc_pass_fail_n      /* synthesis syn_keep=1 */ = crc_pass_fail_n;
wire        ila15rx_hard_err             /* synthesis syn_keep=1 */ = hard_err;
wire        ila15rx_soft_err             /* synthesis syn_keep=1 */ = soft_err;
wire        ila15rx_frame_err            /* synthesis syn_keep=1 */ = frame_err;
wire        ila15rx_payload_err_seen     /* synthesis syn_keep=1 */ = payload_err_seen;
wire        ila15rx_last_err_seen        /* synthesis syn_keep=1 */ = last_err_seen;
wire        ila15rx_hard_err_seen        /* synthesis syn_keep=1 */ = hard_err_seen;
wire        ila15rx_soft_err_seen        /* synthesis syn_keep=1 */ = soft_err_seen;
wire        ila15rx_frame_err_seen       /* synthesis syn_keep=1 */ = frame_err_seen;
wire        ila15rx_crc_err_seen         /* synthesis syn_keep=1 */ = crc_err_seen;
wire        ila15rx_any_err_seen         /* synthesis syn_keep=1 */ = any_err_seen;
wire        ila15rx_any_err_now          /* synthesis syn_keep=1 */ = any_err_now;
wire        ila15rx_test_pass            /* synthesis syn_keep=1 */ = test_pass;

// -----------------------------------------------------------------------------
// SerDes / RoraLink 8B10B IP
// -----------------------------------------------------------------------------
SerDes_Top u_SerDes_Top
(
    .RoraLink_8B10B_Top_reset_i           (sys_rst),
    .RoraLink_8B10B_Top_user_clk_i        (sys_clk),
    .RoraLink_8B10B_Top_init_clk_i        (cfg_clk),
    .RoraLink_8B10B_Top_user_pll_locked_i (gt_pll_ok),
    .RoraLink_8B10B_Top_link_reset_o      (link_reset),
    .RoraLink_8B10B_Top_sys_reset_o       (sys_reset),

    .RoraLink_8B10B_Top_user_rx_data_o    (user_rx_data),
    .RoraLink_8B10B_Top_user_rx_strb_o    (user_rx_strb),
    .RoraLink_8B10B_Top_user_rx_valid_o   (user_rx_valid),
    .RoraLink_8B10B_Top_user_rx_last_o    (user_rx_last),
    .RoraLink_8B10B_Top_crc_pass_fail_n_o (crc_pass_fail_n),
    .RoraLink_8B10B_Top_crc_valid_o       (crc_valid),

    .RoraLink_8B10B_Top_hard_err_o        (hard_err),
    .RoraLink_8B10B_Top_soft_err_o        (soft_err),
    .RoraLink_8B10B_Top_frame_err_o       (frame_err),
    .RoraLink_8B10B_Top_channel_up_o      (channel_up),
    .RoraLink_8B10B_Top_lane_up_o         (lane_up),

    .RoraLink_8B10B_Top_gt_pcs_rx_clk_o   (gt_pcs_rx_clk),
    .RoraLink_8B10B_Top_gt_rx_align_link_o(gt_rx_align_link),
    .RoraLink_8B10B_Top_gt_rx_pma_lock_o  (gt_rx_pma_lock),
    .RoraLink_8B10B_Top_gt_rx_k_lock_o    (gt_rx_k_lock),
    .RoraLink_8B10B_Top_gt_reset_i        (gt_reset),
    .RoraLink_8B10B_Top_gt_pcs_rx_reset_i (gt_pcs_rx_reset),
    .RoraLink_8B10B_Top_gt_pll_lock_o     (gt_pll_ok)
);

endmodule
