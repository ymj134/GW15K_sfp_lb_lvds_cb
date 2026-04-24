`define LVDS_TX_CH 4

module top (
    input  wire                       clk,    // 50M晶振
    input  wire                       rst_n,
    output wire                       lvdsOutClk_p,
    output wire                       lvdsOutClk_n,
    output wire [`LVDS_TX_CH-1:0]     lvdsDataOut_p,
    output wire [`LVDS_TX_CH-1:0]     lvdsDataOut_n,
    output reg                        led
);

    localparam [7:0] C_PASS_GOOD_WORDS = 8'd16;

    // ========================================================================
    // 固定保留原有顶层外形，方便直接替换工程 top
    // ========================================================================
    assign lvdsOutClk_p  = 1'b0;
    assign lvdsOutClk_n  = 1'b0;
    assign lvdsDataOut_p = {`LVDS_TX_CH{1'b0}};
    assign lvdsDataOut_n = {`LVDS_TX_CH{1'b0}};

    // ========================================================================
    // SerDes / RoraLink IP 接口
    // ========================================================================
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

    // ========================================================================
    // TX：固定 8-word 训练序列
    // ========================================================================
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

    // ========================================================================
    // RX：跨字节滑动诊断
    // 先只重点看 raw 与 per-byte bit reverse 这两组。
    // 每组分别检查：
    //   0bit滑动 / 8bit滑动 / 16bit滑动 / 24bit滑动
    // ========================================================================
    reg        rx_seen_sticky;
    reg        hard_err_sticky;
    reg        soft_err_sticky;

    reg        rx_prev_valid;
    reg [31:0] rx_prev_raw;
    reg [31:0] rx_prev_brev;

    wire [31:0] rx_raw_0   = user_rx_data;
    wire [31:0] rx_raw_8   = {rx_prev_raw[23:0],  user_rx_data[31:24]};
    wire [31:0] rx_raw_16  = {rx_prev_raw[15:0],  user_rx_data[31:16]};
    wire [31:0] rx_raw_24  = {rx_prev_raw[7:0],   user_rx_data[31:8]};

    wire [31:0] rx_brev_now = {bitrev8(user_rx_data[31:24]), bitrev8(user_rx_data[23:16]), bitrev8(user_rx_data[15:8]), bitrev8(user_rx_data[7:0])};
    wire [31:0] rx_brev_0   = rx_brev_now;
    wire [31:0] rx_brev_8   = {rx_prev_brev[23:0], rx_brev_now[31:24]};
    wire [31:0] rx_brev_16  = {rx_prev_brev[15:0], rx_brev_now[31:16]};
    wire [31:0] rx_brev_24  = {rx_prev_brev[7:0],  rx_brev_now[31:8]};

    wire [3:0] raw0_dec  = pat_decode(rx_raw_0);
    wire [3:0] raw8_dec  = pat_decode(rx_raw_8);
    wire [3:0] raw16_dec = pat_decode(rx_raw_16);
    wire [3:0] raw24_dec = pat_decode(rx_raw_24);
    wire [3:0] br0_dec   = pat_decode(rx_brev_0);
    wire [3:0] br8_dec   = pat_decode(rx_brev_8);
    wire [3:0] br16_dec  = pat_decode(rx_brev_16);
    wire [3:0] br24_dec  = pat_decode(rx_brev_24);

    wire       raw0_valid  = raw0_dec[3];
    wire [2:0] raw0_idx    = raw0_dec[2:0];
    wire       raw8_valid  = raw8_dec[3];
    wire [2:0] raw8_idx    = raw8_dec[2:0];
    wire       raw16_valid = raw16_dec[3];
    wire [2:0] raw16_idx   = raw16_dec[2:0];
    wire       raw24_valid = raw24_dec[3];
    wire [2:0] raw24_idx   = raw24_dec[2:0];
    wire       br0_valid   = br0_dec[3];
    wire [2:0] br0_idx     = br0_dec[2:0];
    wire       br8_valid   = br8_dec[3];
    wire [2:0] br8_idx     = br8_dec[2:0];
    wire       br16_valid  = br16_dec[3];
    wire [2:0] br16_idx    = br16_dec[2:0];
    wire       br24_valid  = br24_dec[3];
    wire [2:0] br24_idx    = br24_dec[2:0];

    reg        raw0_seen;
    reg [2:0]  raw0_expected_idx;
    reg [7:0]  raw0_good_word_cnt;
    reg        raw0_pass_sticky;

    reg        raw8_seen;
    reg [2:0]  raw8_expected_idx;
    reg [7:0]  raw8_good_word_cnt;
    reg        raw8_pass_sticky;

    reg        raw16_seen;
    reg [2:0]  raw16_expected_idx;
    reg [7:0]  raw16_good_word_cnt;
    reg        raw16_pass_sticky;

    reg        raw24_seen;
    reg [2:0]  raw24_expected_idx;
    reg [7:0]  raw24_good_word_cnt;
    reg        raw24_pass_sticky;

    reg        br0_seen;
    reg [2:0]  br0_expected_idx;
    reg [7:0]  br0_good_word_cnt;
    reg        br0_pass_sticky;

    reg        br8_seen;
    reg [2:0]  br8_expected_idx;
    reg [7:0]  br8_good_word_cnt;
    reg        br8_pass_sticky;

    reg        br16_seen;
    reg [2:0]  br16_expected_idx;
    reg [7:0]  br16_good_word_cnt;
    reg        br16_pass_sticky;

    reg        br24_seen;
    reg [2:0]  br24_expected_idx;
    reg [7:0]  br24_good_word_cnt;
    reg        br24_pass_sticky;

    reg [3:0]  diag_code;
    reg [3:0]  best_code;
    reg [7:0]  best_count;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_seen_sticky   <= 1'b0;
            hard_err_sticky  <= 1'b0;
            soft_err_sticky  <= 1'b0;
            rx_prev_valid    <= 1'b0;
            rx_prev_raw      <= 32'd0;
            rx_prev_brev     <= 32'd0;

            raw0_seen        <= 1'b0;
            raw0_expected_idx<= 3'd0;
            raw0_good_word_cnt <= 8'd0;
            raw0_pass_sticky <= 1'b0;

            raw8_seen        <= 1'b0;
            raw8_expected_idx<= 3'd0;
            raw8_good_word_cnt <= 8'd0;
            raw8_pass_sticky <= 1'b0;

            raw16_seen       <= 1'b0;
            raw16_expected_idx<= 3'd0;
            raw16_good_word_cnt <= 8'd0;
            raw16_pass_sticky<= 1'b0;

            raw24_seen       <= 1'b0;
            raw24_expected_idx<= 3'd0;
            raw24_good_word_cnt <= 8'd0;
            raw24_pass_sticky<= 1'b0;

            br0_seen         <= 1'b0;
            br0_expected_idx <= 3'd0;
            br0_good_word_cnt<= 8'd0;
            br0_pass_sticky  <= 1'b0;

            br8_seen         <= 1'b0;
            br8_expected_idx <= 3'd0;
            br8_good_word_cnt<= 8'd0;
            br8_pass_sticky  <= 1'b0;

            br16_seen        <= 1'b0;
            br16_expected_idx<= 3'd0;
            br16_good_word_cnt<= 8'd0;
            br16_pass_sticky <= 1'b0;

            br24_seen        <= 1'b0;
            br24_expected_idx<= 3'd0;
            br24_good_word_cnt<= 8'd0;
            br24_pass_sticky <= 1'b0;
        end else begin
            if (hard_err)
                hard_err_sticky <= 1'b1;
            if (soft_err)
                soft_err_sticky <= 1'b1;

            if (user_rx_valid) begin
                rx_seen_sticky <= 1'b1;

                // raw 0
                if (raw0_valid) begin
                    if (!raw0_seen || (raw0_idx != raw0_expected_idx)) begin
                        raw0_seen         <= 1'b1;
                        raw0_expected_idx <= idx_next(raw0_idx);
                        raw0_good_word_cnt<= 8'd1;
                        if (C_PASS_GOOD_WORDS == 8'd1)
                            raw0_pass_sticky <= 1'b1;
                    end else begin
                        raw0_expected_idx <= idx_next(raw0_idx);
                        if (raw0_good_word_cnt < C_PASS_GOOD_WORDS)
                            raw0_good_word_cnt <= raw0_good_word_cnt + 8'd1;
                        if (raw0_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                            raw0_pass_sticky <= 1'b1;
                    end
                end else begin
                    raw0_good_word_cnt <= 8'd0;
                end

                // raw + 8bit slide
                if (rx_prev_valid) begin
                    if (raw8_valid) begin
                        if (!raw8_seen || (raw8_idx != raw8_expected_idx)) begin
                            raw8_seen          <= 1'b1;
                            raw8_expected_idx  <= idx_next(raw8_idx);
                            raw8_good_word_cnt <= 8'd1;
                            if (C_PASS_GOOD_WORDS == 8'd1)
                                raw8_pass_sticky <= 1'b1;
                        end else begin
                            raw8_expected_idx <= idx_next(raw8_idx);
                            if (raw8_good_word_cnt < C_PASS_GOOD_WORDS)
                                raw8_good_word_cnt <= raw8_good_word_cnt + 8'd1;
                            if (raw8_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                                raw8_pass_sticky <= 1'b1;
                        end
                    end else begin
                        raw8_good_word_cnt <= 8'd0;
                    end

                    // raw + 16bit slide
                    if (raw16_valid) begin
                        if (!raw16_seen || (raw16_idx != raw16_expected_idx)) begin
                            raw16_seen          <= 1'b1;
                            raw16_expected_idx  <= idx_next(raw16_idx);
                            raw16_good_word_cnt <= 8'd1;
                            if (C_PASS_GOOD_WORDS == 8'd1)
                                raw16_pass_sticky <= 1'b1;
                        end else begin
                            raw16_expected_idx <= idx_next(raw16_idx);
                            if (raw16_good_word_cnt < C_PASS_GOOD_WORDS)
                                raw16_good_word_cnt <= raw16_good_word_cnt + 8'd1;
                            if (raw16_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                                raw16_pass_sticky <= 1'b1;
                        end
                    end else begin
                        raw16_good_word_cnt <= 8'd0;
                    end

                    // raw + 24bit slide
                    if (raw24_valid) begin
                        if (!raw24_seen || (raw24_idx != raw24_expected_idx)) begin
                            raw24_seen          <= 1'b1;
                            raw24_expected_idx  <= idx_next(raw24_idx);
                            raw24_good_word_cnt <= 8'd1;
                            if (C_PASS_GOOD_WORDS == 8'd1)
                                raw24_pass_sticky <= 1'b1;
                        end else begin
                            raw24_expected_idx <= idx_next(raw24_idx);
                            if (raw24_good_word_cnt < C_PASS_GOOD_WORDS)
                                raw24_good_word_cnt <= raw24_good_word_cnt + 8'd1;
                            if (raw24_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                                raw24_pass_sticky <= 1'b1;
                        end
                    end else begin
                        raw24_good_word_cnt <= 8'd0;
                    end

                    // brev 0
                    if (br0_valid) begin
                        if (!br0_seen || (br0_idx != br0_expected_idx)) begin
                            br0_seen          <= 1'b1;
                            br0_expected_idx  <= idx_next(br0_idx);
                            br0_good_word_cnt <= 8'd1;
                            if (C_PASS_GOOD_WORDS == 8'd1)
                                br0_pass_sticky <= 1'b1;
                        end else begin
                            br0_expected_idx <= idx_next(br0_idx);
                            if (br0_good_word_cnt < C_PASS_GOOD_WORDS)
                                br0_good_word_cnt <= br0_good_word_cnt + 8'd1;
                            if (br0_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                                br0_pass_sticky <= 1'b1;
                        end
                    end else begin
                        br0_good_word_cnt <= 8'd0;
                    end

                    // brev + 8bit slide
                    if (br8_valid) begin
                        if (!br8_seen || (br8_idx != br8_expected_idx)) begin
                            br8_seen          <= 1'b1;
                            br8_expected_idx  <= idx_next(br8_idx);
                            br8_good_word_cnt <= 8'd1;
                            if (C_PASS_GOOD_WORDS == 8'd1)
                                br8_pass_sticky <= 1'b1;
                        end else begin
                            br8_expected_idx <= idx_next(br8_idx);
                            if (br8_good_word_cnt < C_PASS_GOOD_WORDS)
                                br8_good_word_cnt <= br8_good_word_cnt + 8'd1;
                            if (br8_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                                br8_pass_sticky <= 1'b1;
                        end
                    end else begin
                        br8_good_word_cnt <= 8'd0;
                    end

                    // brev + 16bit slide
                    if (br16_valid) begin
                        if (!br16_seen || (br16_idx != br16_expected_idx)) begin
                            br16_seen          <= 1'b1;
                            br16_expected_idx  <= idx_next(br16_idx);
                            br16_good_word_cnt <= 8'd1;
                            if (C_PASS_GOOD_WORDS == 8'd1)
                                br16_pass_sticky <= 1'b1;
                        end else begin
                            br16_expected_idx <= idx_next(br16_idx);
                            if (br16_good_word_cnt < C_PASS_GOOD_WORDS)
                                br16_good_word_cnt <= br16_good_word_cnt + 8'd1;
                            if (br16_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                                br16_pass_sticky <= 1'b1;
                        end
                    end else begin
                        br16_good_word_cnt <= 8'd0;
                    end

                    // brev + 24bit slide
                    if (br24_valid) begin
                        if (!br24_seen || (br24_idx != br24_expected_idx)) begin
                            br24_seen          <= 1'b1;
                            br24_expected_idx  <= idx_next(br24_idx);
                            br24_good_word_cnt <= 8'd1;
                            if (C_PASS_GOOD_WORDS == 8'd1)
                                br24_pass_sticky <= 1'b1;
                        end else begin
                            br24_expected_idx <= idx_next(br24_idx);
                            if (br24_good_word_cnt < C_PASS_GOOD_WORDS)
                                br24_good_word_cnt <= br24_good_word_cnt + 8'd1;
                            if (br24_good_word_cnt == (C_PASS_GOOD_WORDS - 8'd1))
                                br24_pass_sticky <= 1'b1;
                        end
                    end else begin
                        br24_good_word_cnt <= 8'd0;
                    end
                end else begin
                    raw8_good_word_cnt  <= 8'd0;
                    raw16_good_word_cnt <= 8'd0;
                    raw24_good_word_cnt <= 8'd0;
                    br0_good_word_cnt   <= 8'd0;
                    br8_good_word_cnt   <= 8'd0;
                    br16_good_word_cnt  <= 8'd0;
                    br24_good_word_cnt  <= 8'd0;
                end

                rx_prev_valid <= 1'b1;
                rx_prev_raw   <= user_rx_data;
                rx_prev_brev  <= rx_brev_now;
            end
        end
    end

    // ========================================================================
    // 诊断结果编码
    // 1: raw_0
    // 2: raw_8
    // 3: raw_16
    // 4: raw_24
    // 5: brev_0
    // 6: brev_8
    // 7: brev_16
    // 8: brev_24
    // ========================================================================
    always @(*) begin
        diag_code = 4'd0;
        if (raw0_pass_sticky)       diag_code = 4'd1;
        else if (raw8_pass_sticky)  diag_code = 4'd2;
        else if (raw16_pass_sticky) diag_code = 4'd3;
        else if (raw24_pass_sticky) diag_code = 4'd4;
        else if (br0_pass_sticky)   diag_code = 4'd5;
        else if (br8_pass_sticky)   diag_code = 4'd6;
        else if (br16_pass_sticky)  diag_code = 4'd7;
        else if (br24_pass_sticky)  diag_code = 4'd8;
    end

    always @(*) begin
        best_code  = 4'd1;
        best_count = raw0_good_word_cnt;

        if (raw8_good_word_cnt > best_count)  begin best_count = raw8_good_word_cnt;  best_code = 4'd2; end
        if (raw16_good_word_cnt > best_count) begin best_count = raw16_good_word_cnt; best_code = 4'd3; end
        if (raw24_good_word_cnt > best_count) begin best_count = raw24_good_word_cnt; best_code = 4'd4; end
        if (br0_good_word_cnt > best_count)   begin best_count = br0_good_word_cnt;   best_code = 4'd5; end
        if (br8_good_word_cnt > best_count)   begin best_count = br8_good_word_cnt;   best_code = 4'd6; end
        if (br16_good_word_cnt > best_count)  begin best_count = br16_good_word_cnt;  best_code = 4'd7; end
        if (br24_good_word_cnt > best_count)  begin best_count = br24_good_word_cnt;  best_code = 4'd8; end
    end

    // ========================================================================
    // LED
    // 灭   : 复位中
    // 慢闪 : 链路没起来
    // 中闪 : 链路起来了，但还没定位到映射
    // 快闪 : 已经有候选在持续增长，但还没到 pass 阈值
    // 常亮 : 已定位映射
    // ========================================================================
    reg [25:0] led_cnt;
    wire led_blink_slow = led_cnt[25];
    wire led_blink_mid  = led_cnt[24];
    wire led_blink_fast = led_cnt[23];

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            led_cnt <= 26'd0;
        else
            led_cnt <= led_cnt + 26'd1;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            led <= 1'b0;
        else if (!serdes_link_ok)
            led <= led_blink_slow;
        else if (diag_code != 4'd0)
            led <= 1'b1;
        else if (best_count >= 8'd4)
            led <= led_blink_fast;
        else
            led <= led_blink_mid;
    end

    // ========================================================================
    // ILA 观察信号
    // 抓取时钟建议：ila1_clk
    // 触发条件建议：ila1_user_rx_valid == 1
    // ========================================================================
    wire        ila1_clk                 = sys_clk;
    wire [2:0]  ila1_tx_pat_idx          = tx_pat_idx;
    wire [31:0] ila1_user_tx_data        = user_tx_data;
    wire [31:0] ila1_user_rx_data        = user_rx_data;

    wire [31:0] ila1_rx_raw_8            = rx_raw_8;
    wire [31:0] ila1_rx_raw_16           = rx_raw_16;
    wire [31:0] ila1_rx_raw_24           = rx_raw_24;
    wire [31:0] ila1_rx_brev_0           = rx_brev_0;
    wire [31:0] ila1_rx_brev_8           = rx_brev_8;
    wire [31:0] ila1_rx_brev_16          = rx_brev_16;
    wire [31:0] ila1_rx_brev_24          = rx_brev_24;

    wire [7:0]  ila1_raw0_good_word_cnt  = raw0_good_word_cnt;
    wire [7:0]  ila1_raw8_good_word_cnt  = raw8_good_word_cnt;
    wire [7:0]  ila1_raw16_good_word_cnt = raw16_good_word_cnt;
    wire [7:0]  ila1_raw24_good_word_cnt = raw24_good_word_cnt;
    wire [7:0]  ila1_br0_good_word_cnt   = br0_good_word_cnt;
    wire [7:0]  ila1_br8_good_word_cnt   = br8_good_word_cnt;
    wire [7:0]  ila1_br16_good_word_cnt  = br16_good_word_cnt;
    wire [7:0]  ila1_br24_good_word_cnt  = br24_good_word_cnt;

    wire [3:0]  ila1_diag_code           = diag_code;
    wire [3:0]  ila1_best_code           = best_code;
    wire [7:0]  ila1_best_count          = best_count;

    wire        ila1_serdes_link_ok      = serdes_link_ok;
    wire        ila1_gt_pll_ok           = gt_pll_ok;
    wire        ila1_channel_up          = channel_up;
    wire        ila1_lane_up             = lane_up;
    wire        ila1_gt_rx_align_link    = gt_rx_align_link;
    wire        ila1_gt_rx_pma_lock      = gt_rx_pma_lock;
    wire        ila1_gt_rx_k_lock        = gt_rx_k_lock;
    wire        ila1_user_tx_valid       = user_tx_valid;
    wire        ila1_user_tx_ready       = user_tx_ready;
    wire        ila1_user_rx_valid       = user_rx_valid;
    wire        ila1_rx_seen_sticky      = rx_seen_sticky;
    wire        ila1_raw0_pass_sticky    = raw0_pass_sticky;
    wire        ila1_raw8_pass_sticky    = raw8_pass_sticky;
    wire        ila1_raw16_pass_sticky   = raw16_pass_sticky;
    wire        ila1_raw24_pass_sticky   = raw24_pass_sticky;
    wire        ila1_br0_pass_sticky     = br0_pass_sticky;
    wire        ila1_br8_pass_sticky     = br8_pass_sticky;
    wire        ila1_br16_pass_sticky    = br16_pass_sticky;
    wire        ila1_br24_pass_sticky    = br24_pass_sticky;
    wire        ila1_hard_err_sticky     = hard_err_sticky;
    wire        ila1_soft_err_sticky     = soft_err_sticky;

endmodule
