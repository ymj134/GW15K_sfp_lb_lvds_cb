`define LVDS_TX_CH 4

module top (
    input  wire                       clk,    // 50M晶振
    input  wire                       rst_n,

    // 保留原有端口，方便直接替换工程 top
    output wire                       lvdsOutClk_p,
    output wire                       lvdsOutClk_n,
    output wire [`LVDS_TX_CH-1:0]     lvdsDataOut_p,
    output wire [`LVDS_TX_CH-1:0]     lvdsDataOut_n,

    output reg                        led
);

    localparam [7:0] C_PASS_GOOD_WORDS = 8'd32;

    //==========================================================================
    // LVDS 相关输出全部拉低，避免改约束
    //==========================================================================
    assign lvdsOutClk_p  = 1'b0;
    assign lvdsOutClk_n  = 1'b0;
    assign lvdsDataOut_p = {`LVDS_TX_CH{1'b0}};
    assign lvdsDataOut_n = {`LVDS_TX_CH{1'b0}};

    //==========================================================================
    // SerDes IP 接口
    //==========================================================================
    wire        user_tx_ready;
    wire [31:0] user_tx_data;
    wire        user_tx_valid;
    wire [31:0] user_rx_data;
    wire        user_rx_valid;
    wire        hard_err;
    wire        soft_err;
    wire        channel_up;
    wire        lane_up;
    wire        gt_pcs_tx_clk;
    wire        gt_pcs_rx_clk;
    wire        gt_pll_ok;
    wire        gt_rx_align_link;
    wire        gt_rx_pma_lock;
    wire        gt_rx_k_lock;
    wire        link_reset_unused;
    wire        sys_reset_unused;

    wire        cfg_clk;
    wire        cfg_pll_lock;
    wire        cfg_rst;

    wire        sys_clk;
    wire        sys_rst;
    wire        sys_rst_n;
    wire        serdes_link_ok;
    wire        tx_fire;

    assign sys_clk        = gt_pcs_tx_clk;
    assign sys_rst_n      = ~sys_rst;
    assign serdes_link_ok = gt_pll_ok & channel_up & lane_up & gt_rx_align_link & gt_rx_pma_lock & gt_rx_k_lock;
    assign user_tx_valid  = 1'b1;
    assign tx_fire        = user_tx_valid & user_tx_ready;

    Gowin_PLL u_cfg_pll (
        .clkin   (clk),
        .clkout0 (cfg_clk),
        .lock    (cfg_pll_lock),
        .mdclk   (clk),
        .reset   (!rst_n)
    );

    reset_gen u_reset_gen1 (
        .i_clk1 (cfg_clk),
        .i_lock (cfg_pll_lock),
        .o_rst1 (cfg_rst)
    );

    reset_gen u_reset_gen2 (
        .i_clk1 (sys_clk),
        .i_lock (gt_pll_ok),
        .o_rst1 (sys_rst)
    );

    SerDes_Top u_SerDes_Top (
        .RoraLink_8B10B_Top_link_reset_o      (link_reset_unused),
        .RoraLink_8B10B_Top_sys_reset_o       (sys_reset_unused),
        .RoraLink_8B10B_Top_user_tx_ready_o   (user_tx_ready),
        .RoraLink_8B10B_Top_user_rx_data_o    (user_rx_data),
        .RoraLink_8B10B_Top_user_rx_valid_o   (user_rx_valid),
        .RoraLink_8B10B_Top_hard_err_o        (hard_err),
        .RoraLink_8B10B_Top_soft_err_o        (soft_err),
        .RoraLink_8B10B_Top_channel_up_o      (channel_up),
        .RoraLink_8B10B_Top_lane_up_o         (lane_up),
        .RoraLink_8B10B_Top_gt_pcs_tx_clk_o   (gt_pcs_tx_clk),
        .RoraLink_8B10B_Top_gt_pcs_rx_clk_o   (gt_pcs_rx_clk),
        .RoraLink_8B10B_Top_gt_pll_lock_o     (gt_pll_ok),
        .RoraLink_8B10B_Top_gt_rx_align_link_o(gt_rx_align_link),
        .RoraLink_8B10B_Top_gt_rx_pma_lock_o  (gt_rx_pma_lock),
        .RoraLink_8B10B_Top_gt_rx_k_lock_o    (gt_rx_k_lock),

        .RoraLink_8B10B_Top_user_clk_i        (sys_clk),
        .RoraLink_8B10B_Top_init_clk_i        (cfg_clk),

        .RoraLink_8B10B_Top_reset_i           (cfg_rst),
        .RoraLink_8B10B_Top_user_pll_locked_i (sys_rst_n),

        .RoraLink_8B10B_Top_user_tx_data_i    (user_tx_data),
        .RoraLink_8B10B_Top_user_tx_valid_i   (user_tx_valid),

        .RoraLink_8B10B_Top_gt_reset_i        (1'b0),
        .RoraLink_8B10B_Top_gt_pcs_tx_reset_i (1'b0),
        .RoraLink_8B10B_Top_gt_pcs_rx_reset_i (1'b0)
    );

    //==========================================================================
    // Pattern 发生器：发固定 8-word 循环序列，方便判断字节序 / 位序 / 边界
    //==========================================================================
    reg [2:0] tx_pat_idx;

    function [31:0] pat_word;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: pat_word = 32'h12_34_56_78;
                3'd1: pat_word = 32'h9A_BC_DE_F0;
                3'd2: pat_word = 32'h0F_1E_2D_3C;
                3'd3: pat_word = 32'h4B_5A_69_96;
                3'd4: pat_word = 32'hA5_5A_C3_3C;
                3'd5: pat_word = 32'h77_88_99_AA;
                3'd6: pat_word = 32'h13_57_9B_DF;
                3'd7: pat_word = 32'h24_68_AC_E0;
                default: pat_word = 32'h12_34_56_78;
            endcase
        end
    endfunction

    function [7:0] bitrev8;
        input [7:0] din;
        begin
            bitrev8 = {din[0], din[1], din[2], din[3], din[4], din[5], din[6], din[7]};
        end
    endfunction

    function [3:0] pat_decode;
        input [31:0] din;
        begin
            case (din)
                32'h12_34_56_78: pat_decode = {1'b1, 3'd0};
                32'h9A_BC_DE_F0: pat_decode = {1'b1, 3'd1};
                32'h0F_1E_2D_3C: pat_decode = {1'b1, 3'd2};
                32'h4B_5A_69_96: pat_decode = {1'b1, 3'd3};
                32'hA5_5A_C3_3C: pat_decode = {1'b1, 3'd4};
                32'h77_88_99_AA: pat_decode = {1'b1, 3'd5};
                32'h13_57_9B_DF: pat_decode = {1'b1, 3'd6};
                32'h24_68_AC_E0: pat_decode = {1'b1, 3'd7};
                default:         pat_decode = {1'b0, 3'd0};
            endcase
        end
    endfunction

    function [2:0] idx_next;
        input [2:0] idx;
        begin
            if (idx == 3'd7)
                idx_next = 3'd0;
            else
                idx_next = idx + 3'd1;
        end
    endfunction

    assign user_tx_data = pat_word(tx_pat_idx);

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            tx_pat_idx <= 3'd0;
        else if (tx_fire)
            tx_pat_idx <= idx_next(tx_pat_idx);
    end

    //==========================================================================
    // RX 映射诊断
    // raw              : 原始 user_rx_data
    // bswap            : 字节交换
    // brev             : 每字节 bit reverse
    // bswap + brev     : 字节交换后再每字节 bit reverse
    //==========================================================================
    wire [31:0] rx_raw_data        = user_rx_data;
    wire [31:0] rx_bswap_data      = {user_rx_data[7:0], user_rx_data[15:8], user_rx_data[23:16], user_rx_data[31:24]};
    wire [31:0] rx_brev_data       = {bitrev8(user_rx_data[31:24]), bitrev8(user_rx_data[23:16]), bitrev8(user_rx_data[15:8]), bitrev8(user_rx_data[7:0])};
    wire [31:0] rx_bswap_brev_data = {bitrev8(user_rx_data[7:0]),  bitrev8(user_rx_data[15:8]),  bitrev8(user_rx_data[23:16]),  bitrev8(user_rx_data[31:24])};

    wire [3:0] raw_decode        = pat_decode(rx_raw_data);
    wire [3:0] bswap_decode      = pat_decode(rx_bswap_data);
    wire [3:0] brev_decode       = pat_decode(rx_brev_data);
    wire [3:0] bswap_brev_decode = pat_decode(rx_bswap_brev_data);

    wire       raw_valid         = raw_decode[3];
    wire [2:0] raw_idx           = raw_decode[2:0];
    wire       bswap_valid       = bswap_decode[3];
    wire [2:0] bswap_idx         = bswap_decode[2:0];
    wire       brev_valid        = brev_decode[3];
    wire [2:0] brev_idx          = brev_decode[2:0];
    wire       bswap_brev_valid  = bswap_brev_decode[3];
    wire [2:0] bswap_brev_idx    = bswap_brev_decode[2:0];

    reg        rx_seen_sticky;
    reg        hard_err_sticky;
    reg        soft_err_sticky;

    reg        raw_seen;
    reg [2:0]  raw_expected_idx;
    reg [7:0]  raw_good_word_cnt;
    reg        raw_pass_sticky;

    reg        bswap_seen;
    reg [2:0]  bswap_expected_idx;
    reg [7:0]  bswap_good_word_cnt;
    reg        bswap_pass_sticky;

    reg        brev_seen;
    reg [2:0]  brev_expected_idx;
    reg [7:0]  brev_good_word_cnt;
    reg        brev_pass_sticky;

    reg        bswap_brev_seen;
    reg [2:0]  bswap_brev_expected_idx;
    reg [7:0]  bswap_brev_good_word_cnt;
    reg        bswap_brev_pass_sticky;

    reg [2:0]  diag_code;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_seen_sticky           <= 1'b0;
            hard_err_sticky          <= 1'b0;
            soft_err_sticky          <= 1'b0;

            raw_seen                 <= 1'b0;
            raw_expected_idx         <= 3'd0;
            raw_good_word_cnt        <= 8'd0;
            raw_pass_sticky          <= 1'b0;

            bswap_seen               <= 1'b0;
            bswap_expected_idx       <= 3'd0;
            bswap_good_word_cnt      <= 8'd0;
            bswap_pass_sticky        <= 1'b0;

            brev_seen                <= 1'b0;
            brev_expected_idx        <= 3'd0;
            brev_good_word_cnt       <= 8'd0;
            brev_pass_sticky         <= 1'b0;

            bswap_brev_seen          <= 1'b0;
            bswap_brev_expected_idx  <= 3'd0;
            bswap_brev_good_word_cnt <= 8'd0;
            bswap_brev_pass_sticky   <= 1'b0;
        end else begin
            if (hard_err)
                hard_err_sticky <= 1'b1;
            if (soft_err)
                soft_err_sticky <= 1'b1;

            if (user_rx_valid) begin
                rx_seen_sticky <= 1'b1;

                // raw
                if (raw_valid) begin
                    if (!raw_seen) begin
                        raw_seen          <= 1'b1;
                        raw_expected_idx  <= idx_next(raw_idx);
                        raw_good_word_cnt <= 8'd1;
                    end else if (raw_idx == raw_expected_idx) begin
                        raw_expected_idx <= idx_next(raw_idx);
                        if (raw_good_word_cnt < C_PASS_GOOD_WORDS)
                            raw_good_word_cnt <= raw_good_word_cnt + 8'd1;
                        if (raw_good_word_cnt >= (C_PASS_GOOD_WORDS - 8'd1))
                            raw_pass_sticky <= 1'b1;
                    end else begin
                        raw_seen          <= 1'b1;
                        raw_expected_idx  <= idx_next(raw_idx);
                        raw_good_word_cnt <= 8'd1;
                    end
                end else begin
                    raw_good_word_cnt <= 8'd0;
                end

                // bswap
                if (bswap_valid) begin
                    if (!bswap_seen) begin
                        bswap_seen          <= 1'b1;
                        bswap_expected_idx  <= idx_next(bswap_idx);
                        bswap_good_word_cnt <= 8'd1;
                    end else if (bswap_idx == bswap_expected_idx) begin
                        bswap_expected_idx <= idx_next(bswap_idx);
                        if (bswap_good_word_cnt < C_PASS_GOOD_WORDS)
                            bswap_good_word_cnt <= bswap_good_word_cnt + 8'd1;
                        if (bswap_good_word_cnt >= (C_PASS_GOOD_WORDS - 8'd1))
                            bswap_pass_sticky <= 1'b1;
                    end else begin
                        bswap_seen          <= 1'b1;
                        bswap_expected_idx  <= idx_next(bswap_idx);
                        bswap_good_word_cnt <= 8'd1;
                    end
                end else begin
                    bswap_good_word_cnt <= 8'd0;
                end

                // brev
                if (brev_valid) begin
                    if (!brev_seen) begin
                        brev_seen          <= 1'b1;
                        brev_expected_idx  <= idx_next(brev_idx);
                        brev_good_word_cnt <= 8'd1;
                    end else if (brev_idx == brev_expected_idx) begin
                        brev_expected_idx <= idx_next(brev_idx);
                        if (brev_good_word_cnt < C_PASS_GOOD_WORDS)
                            brev_good_word_cnt <= brev_good_word_cnt + 8'd1;
                        if (brev_good_word_cnt >= (C_PASS_GOOD_WORDS - 8'd1))
                            brev_pass_sticky <= 1'b1;
                    end else begin
                        brev_seen          <= 1'b1;
                        brev_expected_idx  <= idx_next(brev_idx);
                        brev_good_word_cnt <= 8'd1;
                    end
                end else begin
                    brev_good_word_cnt <= 8'd0;
                end

                // bswap + brev
                if (bswap_brev_valid) begin
                    if (!bswap_brev_seen) begin
                        bswap_brev_seen          <= 1'b1;
                        bswap_brev_expected_idx  <= idx_next(bswap_brev_idx);
                        bswap_brev_good_word_cnt <= 8'd1;
                    end else if (bswap_brev_idx == bswap_brev_expected_idx) begin
                        bswap_brev_expected_idx <= idx_next(bswap_brev_idx);
                        if (bswap_brev_good_word_cnt < C_PASS_GOOD_WORDS)
                            bswap_brev_good_word_cnt <= bswap_brev_good_word_cnt + 8'd1;
                        if (bswap_brev_good_word_cnt >= (C_PASS_GOOD_WORDS - 8'd1))
                            bswap_brev_pass_sticky <= 1'b1;
                    end else begin
                        bswap_brev_seen          <= 1'b1;
                        bswap_brev_expected_idx  <= idx_next(bswap_brev_idx);
                        bswap_brev_good_word_cnt <= 8'd1;
                    end
                end else begin
                    bswap_brev_good_word_cnt <= 8'd0;
                end
            end
        end
    end

    always @(*) begin
        if (raw_pass_sticky)
            diag_code = 3'd1;
        else if (bswap_pass_sticky)
            diag_code = 3'd2;
        else if (brev_pass_sticky)
            diag_code = 3'd3;
        else if (bswap_brev_pass_sticky)
            diag_code = 3'd4;
        else
            diag_code = 3'd0;
    end

    //==========================================================================
    // LED 指示
    // 灭      : 复位中 / PLL未好
    // 慢闪    : 链路未起来
    // 常亮    : raw 直接通过，说明 RX 与 TX 完全同格式
    // 快闪    : 链路通，但只有变换后才通过，说明存在格式映射问题
    // 中闪    : 链路通、见到 RX，但 아직未判断出来
    //==========================================================================
    reg [25:0] led_cnt;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            led_cnt <= 26'd0;
        else
            led_cnt <= led_cnt + 26'd1;
    end

    wire led_blink_slow = led_cnt[25];
    wire led_blink_mid  = led_cnt[24];
    wire led_blink_fast = led_cnt[23];

    wire map_pass_nonraw = bswap_pass_sticky | brev_pass_sticky | bswap_brev_pass_sticky;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            led <= 1'b0;
        else if (!serdes_link_ok)
            led <= led_blink_slow;
        else if (raw_pass_sticky)
            led <= 1'b1;
        else if (map_pass_nonraw)
            led <= led_blink_fast;
        else
            led <= led_blink_mid;
    end

    //==========================================================================
    // ILA 观察信号
    // diag_code:
    //   0 = 还没判断出来
    //   1 = raw 直接匹配
    //   2 = byte swap 后匹配
    //   3 = 每字节 bit reverse 后匹配
    //   4 = byte swap + bit reverse 后匹配
    //==========================================================================
    wire        ila1_clk                     = sys_clk;
    wire        ila1_serdes_link_ok          = serdes_link_ok;
    wire        ila1_gt_pll_ok               = gt_pll_ok;
    wire        ila1_channel_up              = channel_up;
    wire        ila1_lane_up                 = lane_up;
    wire        ila1_gt_rx_align_link        = gt_rx_align_link;
    wire        ila1_gt_rx_pma_lock          = gt_rx_pma_lock;
    wire        ila1_gt_rx_k_lock            = gt_rx_k_lock;

    wire        ila1_user_tx_valid           = user_tx_valid;
    wire        ila1_user_tx_ready           = user_tx_ready;
    wire [2:0]  ila1_tx_pat_idx              = tx_pat_idx;
    wire [31:0] ila1_user_tx_data            = user_tx_data;

    wire        ila1_user_rx_valid           = user_rx_valid;
    wire [31:0] ila1_user_rx_data            = rx_raw_data;
    wire [31:0] ila1_rx_bswap_data           = rx_bswap_data;
    wire [31:0] ila1_rx_brev_data            = rx_brev_data;
    wire [31:0] ila1_rx_bswap_brev_data      = rx_bswap_brev_data;

    wire [7:0]  ila1_raw_good_word_cnt       = raw_good_word_cnt;
    wire [7:0]  ila1_bswap_good_word_cnt     = bswap_good_word_cnt;
    wire [7:0]  ila1_brev_good_word_cnt      = brev_good_word_cnt;
    wire [7:0]  ila1_bswap_brev_good_word_cnt= bswap_brev_good_word_cnt;

    wire        ila1_raw_pass_sticky         = raw_pass_sticky;
    wire        ila1_bswap_pass_sticky       = bswap_pass_sticky;
    wire        ila1_brev_pass_sticky        = brev_pass_sticky;
    wire        ila1_bswap_brev_pass_sticky  = bswap_brev_pass_sticky;
    wire [2:0]  ila1_diag_code               = diag_code;

    wire        ila1_rx_seen_sticky          = rx_seen_sticky;
    wire        ila1_hard_err_sticky         = hard_err_sticky;
    wire        ila1_soft_err_sticky         = soft_err_sticky;

endmodule
