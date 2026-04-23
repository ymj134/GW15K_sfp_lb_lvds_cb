`define LVDS_TX_CH 4

module top
(
    input                       clk,
    input                       rst_n,

    // LVDS TX
    output                      lvdsOutClk_p,
    output                      lvdsOutClk_n,
    output [`LVDS_TX_CH-1:0]    lvdsDataOut_p,
    output [`LVDS_TX_CH-1:0]    lvdsDataOut_n,

    // status
    output reg                  led
);

    //==========================================================================
    // 参数
    //==========================================================================
    localparam [31:0] T1S = 32'd69_999_999;

    // 1024x600 timing（保持你现有本地点屏）
    localparam [11:0] C_H_TOTAL  = 12'd1344;
    localparam [11:0] C_H_SYNC   = 12'd24;
    localparam [11:0] C_H_BPORCH = 12'd160;
    localparam [11:0] C_H_RES    = 12'd1024;

    localparam [11:0] C_V_TOTAL  = 12'd635;
    localparam [11:0] C_V_SYNC   = 12'd2;
    localparam [11:0] C_V_BPORCH = 12'd23;
    localparam [11:0] C_V_RES    = 12'd600;

    // 用 0x96 做头字节，便于检查 bit 顺序/错码
    localparam [7:0]  C_TX_HDR            = 8'h96;
    // 连续匹配到这么多拍，就认为链路数据自检通过
    localparam [15:0] C_PASS_MATCH_TH     = 16'd256;
    // 已经锁定后，若长时间收不到 user_rx_valid，就判为超时
    localparam [19:0] C_RX_IDLE_TIMEOUT   = 20'd1_048_575;

    //==========================================================================
    // 1) LVDS pixel clock
    //==========================================================================
    wire lvds_eclk;
    wire pixclk;
    wire pll_lock;

    Gowin_PLL u_PLL_LVDS_TX
    (
        .clkin      (clk),
        .clkout0    (lvds_eclk),
        .lock       (pll_lock),
        .mdclk      (clk),
        .reset      (!rst_n)
    );

    CLKDIV CLKDIV_inst
    (
        .RESETN     (rst_n),
        .HCLKIN     (lvds_eclk),
        .CALIB      (1'b0),
        .CLKOUT     (pixclk)
    );
    defparam CLKDIV_inst.DIV_MODE = "3.5";

    wire pixel_rst;
    wire pixel_rst_n;

    reset_gen u_pixel_reset_gen
    (
        .i_clk1     (pixclk),
        .i_lock     (pll_lock & rst_n),
        .o_rst1     (pixel_rst)
    );

    assign pixel_rst_n = ~pixel_rst;

    //==========================================================================
    // 2) 本地 testpattern（仅保留本地点屏）
    //==========================================================================
    reg  [31:0] count;
    reg  [2:0]  col_cnt;

    wire [7:0] tp_r;
    wire [7:0] tp_g;
    wire [7:0] tp_b;
    wire       tp_de;
    wire       tp_hs;
    wire       tp_vs;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            count <= 32'd0;
        else if(count == T1S)
            count <= 32'd0;
        else
            count <= count + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            col_cnt <= 3'd0;
        else if(count == T1S)
            col_cnt <= col_cnt + 1'b1;
    end

    testpattern testpattern_inst
    (
        .I_pxl_clk   (pixclk),
        .I_rst_n     (pixel_rst_n),
        .I_mode      (col_cnt),
        .I_single_r  (8'd0),
        .I_single_g  (8'd0),
        .I_single_b  (8'd255),
        .I_h_total   (C_H_TOTAL),
        .I_h_sync    (C_H_SYNC),
        .I_h_bporch  (C_H_BPORCH),
        .I_h_res     (C_H_RES),
        .I_v_total   (C_V_TOTAL),
        .I_v_sync    (C_V_SYNC),
        .I_v_bporch  (C_V_BPORCH),
        .I_v_res     (C_V_RES),
        .I_hs_pol    (1'b1),
        .I_vs_pol    (1'b1),
        .O_de        (tp_de),
        .O_hs        (tp_hs),
        .O_vs        (tp_vs),
        .O_data_r    (tp_r),
        .O_data_g    (tp_g),
        .O_data_b    (tp_b)
    );

    //==========================================================================
    // 3) SerDes 接口与状态
    //==========================================================================
    wire [31:0] user_tx_data;
    wire        user_tx_valid;
    wire        user_tx_ready;

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

    // 注意：RoraLink 的 user TX / user RX 侧都应该按 user_clk_i 所在域理解。
    // 这里 user_clk_i 继续接 gt_pcs_tx_clk，所以收发和 checker 全部统一在 tx_clk 域。
    wire        tx_clk;
    wire        rx_clk;
    wire        tx_rst;
    wire        tx_rst_n;

    wire        gt_reset;
    wire        gt_pcs_tx_reset;
    wire        gt_pcs_rx_reset;

    assign tx_clk          = gt_pcs_tx_clk;
    assign rx_clk          = gt_pcs_rx_clk;
    assign gt_reset        = 1'b0;
    assign gt_pcs_tx_reset = 1'b0;
    assign gt_pcs_rx_reset = 1'b0;

    reset_gen u_tx_reset_gen
    (
        .i_clk1     (tx_clk),
        .i_lock     (rst_n & pll_lock & gt_pll_ok),
        .o_rst1     (tx_rst)
    );
    assign tx_rst_n = ~tx_rst;

    SerDes_Top u_SerDes_Top
    (
        .RoraLink_8B10B_Top_link_reset_o          (link_reset_unused),
        .RoraLink_8B10B_Top_sys_reset_o           (sys_reset_unused),
        .RoraLink_8B10B_Top_user_tx_ready_o       (user_tx_ready),
        .RoraLink_8B10B_Top_user_rx_data_o        (user_rx_data),
        .RoraLink_8B10B_Top_user_rx_valid_o       (user_rx_valid),
        .RoraLink_8B10B_Top_hard_err_o            (hard_err),
        .RoraLink_8B10B_Top_soft_err_o            (soft_err),
        .RoraLink_8B10B_Top_channel_up_o          (channel_up),
        .RoraLink_8B10B_Top_lane_up_o             (lane_up),
        .RoraLink_8B10B_Top_gt_pcs_tx_clk_o       (gt_pcs_tx_clk),
        .RoraLink_8B10B_Top_gt_pcs_rx_clk_o       (gt_pcs_rx_clk),
        .RoraLink_8B10B_Top_gt_pll_lock_o         (gt_pll_ok),
        .RoraLink_8B10B_Top_gt_rx_align_link_o    (gt_rx_align_link),
        .RoraLink_8B10B_Top_gt_rx_pma_lock_o      (gt_rx_pma_lock),
        .RoraLink_8B10B_Top_gt_rx_k_lock_o        (gt_rx_k_lock),

        .RoraLink_8B10B_Top_user_clk_i            (tx_clk),
        .RoraLink_8B10B_Top_init_clk_i            (clk),
        .RoraLink_8B10B_Top_reset_i               (tx_rst),
        .RoraLink_8B10B_Top_user_pll_locked_i     (gt_pll_ok),
        .RoraLink_8B10B_Top_user_tx_data_i        (user_tx_data),
        .RoraLink_8B10B_Top_user_tx_valid_i       (user_tx_valid),
        .RoraLink_8B10B_Top_gt_reset_i            (gt_reset),
        .RoraLink_8B10B_Top_gt_pcs_tx_reset_i     (gt_pcs_tx_reset),
        .RoraLink_8B10B_Top_gt_pcs_rx_reset_i     (gt_pcs_rx_reset)
    );

    wire serdes_link_ok;
    assign serdes_link_ok =
        channel_up       &
        lane_up          &
        gt_pll_ok        &
        gt_rx_align_link &
        gt_rx_pma_lock   &
        gt_rx_k_lock;

    //==========================================================================
    // 4) TX 域：发送固定头 + 24bit 递增计数
    //==========================================================================
    reg  [23:0] tx_cnt;
    reg  [31:0] tx_last_fire_data;
    reg         tx_seen_sticky;

    assign user_tx_data  = {C_TX_HDR, tx_cnt};
    assign user_tx_valid = tx_rst_n;

    always @(posedge tx_clk or negedge tx_rst_n) begin
        if(!tx_rst_n) begin
            tx_cnt            <= 24'd0;
            tx_last_fire_data <= 32'd0;
            tx_seen_sticky    <= 1'b0;
        end
        else begin
            if(user_tx_valid && user_tx_ready) begin
                tx_last_fire_data <= {C_TX_HDR, tx_cnt};
                tx_cnt            <= tx_cnt + 24'd1;
                tx_seen_sticky    <= 1'b1;
            end
        end
    end

    //==========================================================================
    // 5) RX 自检逻辑（重要：改到 user_clk/tx_clk 域，不再放在 gt_pcs_rx_clk 域）
    //==========================================================================
    reg  [31:0] rx_last_data;
    reg  [31:0] rx_expected_data_at_err;
    reg  [31:0] rx_last_error_data;
    reg  [23:0] rx_expected_cnt;

    reg         rx_seen_sticky;
    reg         rx_lock_sticky;
    reg         rx_match_pulse;
    reg         rx_pass_sticky;
    reg         rx_fail_sticky;
    reg         rx_mismatch_sticky;
    reg         rx_header_err_sticky;
    reg         rx_idle_timeout_sticky;
    reg         hard_err_sticky_rx;
    reg         soft_err_sticky_rx;

    reg  [15:0] rx_good_match_run_cnt;
    reg  [31:0] rx_total_word_cnt;
    reg  [31:0] rx_good_word_cnt;
    reg  [31:0] rx_bad_word_cnt;
    reg  [19:0] rx_idle_gap_cnt;

    always @(posedge tx_clk or negedge tx_rst_n) begin
        if(!tx_rst_n) begin
            rx_last_data            <= 32'd0;
            rx_expected_data_at_err <= 32'd0;
            rx_last_error_data      <= 32'd0;
            rx_expected_cnt         <= 24'd0;

            rx_seen_sticky          <= 1'b0;
            rx_lock_sticky          <= 1'b0;
            rx_match_pulse          <= 1'b0;
            rx_pass_sticky          <= 1'b0;
            rx_fail_sticky          <= 1'b0;
            rx_mismatch_sticky      <= 1'b0;
            rx_header_err_sticky    <= 1'b0;
            rx_idle_timeout_sticky  <= 1'b0;
            hard_err_sticky_rx      <= 1'b0;
            soft_err_sticky_rx      <= 1'b0;

            rx_good_match_run_cnt   <= 16'd0;
            rx_total_word_cnt       <= 32'd0;
            rx_good_word_cnt        <= 32'd0;
            rx_bad_word_cnt         <= 32'd0;
            rx_idle_gap_cnt         <= 20'd0;
        end
        else begin
            rx_match_pulse <= 1'b0;

            if(hard_err) begin
                hard_err_sticky_rx <= 1'b1;
                rx_fail_sticky     <= 1'b1;
            end

            if(soft_err) begin
                soft_err_sticky_rx <= 1'b1;
                rx_fail_sticky     <= 1'b1;
            end

            if(!serdes_link_ok) begin
                // 链路没 fully up 时，只清运行态锁定，不清 sticky 结果
                rx_lock_sticky        <= 1'b0;
                rx_expected_cnt       <= 24'd0;
                rx_good_match_run_cnt <= 16'd0;
                rx_idle_gap_cnt       <= 20'd0;
            end
            else begin
                if(user_rx_valid) begin
                    rx_last_data      <= user_rx_data;
                    rx_seen_sticky    <= 1'b1;
                    rx_total_word_cnt <= rx_total_word_cnt + 1'b1;
                    rx_idle_gap_cnt   <= 20'd0;

                    if(user_rx_data[31:24] != C_TX_HDR) begin
                        rx_header_err_sticky    <= 1'b1;
                        rx_fail_sticky          <= 1'b1;
                        rx_last_error_data      <= user_rx_data;
                        rx_expected_data_at_err <= {C_TX_HDR, rx_expected_cnt};
                        rx_bad_word_cnt         <= rx_bad_word_cnt + 1'b1;
                        rx_lock_sticky          <= 1'b0;
                        rx_expected_cnt         <= 24'd0;
                        rx_good_match_run_cnt   <= 16'd0;
                    end
                    else if(!rx_lock_sticky) begin
                        // 第一次看到合法头，建立锁定，不在这一拍就判 pass
                        rx_lock_sticky        <= 1'b1;
                        rx_expected_cnt       <= user_rx_data[23:0] + 24'd1;
                        rx_good_match_run_cnt <= 16'd0;
                    end
                    else begin
                        if(user_rx_data[23:0] == rx_expected_cnt) begin
                            rx_match_pulse    <= 1'b1;
                            rx_good_word_cnt  <= rx_good_word_cnt + 1'b1;

                            if(rx_good_match_run_cnt != 16'hFFFF)
                                rx_good_match_run_cnt <= rx_good_match_run_cnt + 1'b1;

                            if(rx_good_match_run_cnt >= (C_PASS_MATCH_TH - 16'd1))
                                rx_pass_sticky <= 1'b1;
                        end
                        else begin
                            rx_mismatch_sticky      <= 1'b1;
                            rx_fail_sticky          <= 1'b1;
                            rx_last_error_data      <= user_rx_data;
                            rx_expected_data_at_err <= {C_TX_HDR, rx_expected_cnt};
                            rx_bad_word_cnt         <= rx_bad_word_cnt + 1'b1;
                            rx_good_match_run_cnt   <= 16'd0;
                        end

                        // 不管本拍 match 还是 mismatch，都以当前收到的数据重新对齐下一拍期望值
                        rx_expected_cnt <= user_rx_data[23:0] + 24'd1;
                    end
                end
                else begin
                    if(rx_lock_sticky) begin
                        if(rx_idle_gap_cnt != C_RX_IDLE_TIMEOUT)
                            rx_idle_gap_cnt <= rx_idle_gap_cnt + 1'b1;

                        if(rx_idle_gap_cnt == (C_RX_IDLE_TIMEOUT - 20'd1)) begin
                            rx_idle_timeout_sticky <= 1'b1;
                            rx_fail_sticky         <= 1'b1;
                            rx_good_match_run_cnt  <= 16'd0;
                        end
                    end
                    else begin
                        rx_idle_gap_cnt <= 20'd0;
                    end
                end
            end
        end
    end

    wire checker_ok;
    assign checker_ok = serdes_link_ok & rx_pass_sticky & (~rx_fail_sticky);

    //==========================================================================
    // 6) LVDS 输出：始终显示本地图案
    //==========================================================================
    rgb_2_lvds u_rgb2lvds
    (
        .rst_n      (pixel_rst_n),
        .rgb_clk    (pixclk),
        .rgb_vs     (tp_vs),
        .rgb_hs     (tp_hs),
        .rgb_de     (tp_de),
        .rgb_data   ({tp_r, tp_g, tp_b}),
        .lvds_eclk  (lvds_eclk),

        .lvds_clk_p (lvdsOutClk_p),
        .lvds_clk_n (lvdsOutClk_n),
        .lvds_d0_p  (lvdsDataOut_p[0]),
        .lvds_d0_n  (lvdsDataOut_n[0]),
        .lvds_d1_p  (lvdsDataOut_p[1]),
        .lvds_d1_n  (lvdsDataOut_n[1]),
        .lvds_d2_p  (lvdsDataOut_p[2]),
        .lvds_d2_n  (lvdsDataOut_n[2]),
        .lvds_d3_p  (lvdsDataOut_p[3]),
        .lvds_d3_n  (lvdsDataOut_n[3])
    );

    //==========================================================================
    // 7) LED（先把 tx_clk 域的状态同步到 clk 域，只给 LED 用）
    //    灭    : 外部复位/PLL 未就绪
    //    慢闪  : SerDes 链路未 fully up
    //    快闪  : 链路 up 了，但 RX 还没锁定/还没通过自检
    //    常亮  : 自检通过，且没出现 sticky fail
    //    快闪  : sticky fail（header/mismatch/timeout/hard/soft err）
    //==========================================================================
    wire [9:0] led_status_bus_txclk;
    assign led_status_bus_txclk = {
        serdes_link_ok,
        rx_seen_sticky,
        rx_lock_sticky,
        rx_pass_sticky,
        rx_fail_sticky,
        rx_header_err_sticky,
        rx_mismatch_sticky,
        rx_idle_timeout_sticky,
        hard_err_sticky_rx,
        soft_err_sticky_rx
    };

    reg [9:0] led_status_bus_meta;
    reg [9:0] led_status_bus_sync;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            led_status_bus_meta <= 10'd0;
            led_status_bus_sync <= 10'd0;
        end
        else begin
            led_status_bus_meta <= led_status_bus_txclk;
            led_status_bus_sync <= led_status_bus_meta;
        end
    end

    wire led_serdes_link_ok_sync     = led_status_bus_sync[9];
    wire led_rx_seen_sync            = led_status_bus_sync[8];
    wire led_rx_lock_sync            = led_status_bus_sync[7];
    wire led_rx_pass_sync            = led_status_bus_sync[6];
    wire led_rx_fail_sync            = led_status_bus_sync[5];
    wire led_rx_header_err_sync      = led_status_bus_sync[4];
    wire led_rx_mismatch_sync        = led_status_bus_sync[3];
    wire led_rx_idle_timeout_sync    = led_status_bus_sync[2];
    wire led_hard_err_sync           = led_status_bus_sync[1];
    wire led_soft_err_sync           = led_status_bus_sync[0];

    reg [25:0] led_cnt;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            led_cnt <= 26'd0;
        else
            led_cnt <= led_cnt + 1'b1;
    end

    wire led_blink_slow = led_cnt[25];
    wire led_blink_fast = led_cnt[23];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            led <= 1'b0;
        else if(!pll_lock)
            led <= 1'b0;
        else if(!led_serdes_link_ok_sync)
            led <= led_blink_slow;
        else if(led_rx_fail_sync || led_rx_header_err_sync || led_rx_mismatch_sync || led_rx_idle_timeout_sync || led_hard_err_sync || led_soft_err_sync)
            led <= led_blink_fast;
        else if(!led_rx_seen_sync || !led_rx_lock_sync || !led_rx_pass_sync)
            led <= led_blink_fast;
        else
            led <= 1'b1;
    end

    //==========================================================================
    // 8) ILA1：TX / user_clk 域，统一前缀 ila1_
    //==========================================================================
    (* keep = "true" *) wire        ila1_clk                = tx_clk;
    (* keep = "true" *) wire        ila1_tx_rst_n           = tx_rst_n;

    (* keep = "true" *) wire        ila1_gt_pll_ok          = gt_pll_ok;
    (* keep = "true" *) wire        ila1_channel_up         = channel_up;
    (* keep = "true" *) wire        ila1_lane_up            = lane_up;
    (* keep = "true" *) wire        ila1_gt_rx_align_link   = gt_rx_align_link;
    (* keep = "true" *) wire        ila1_gt_rx_pma_lock     = gt_rx_pma_lock;
    (* keep = "true" *) wire        ila1_gt_rx_k_lock       = gt_rx_k_lock;
    (* keep = "true" *) wire        ila1_serdes_link_ok     = serdes_link_ok;
    (* keep = "true" *) wire        ila1_checker_ok         = checker_ok;
    (* keep = "true" *) wire        ila1_hard_err           = hard_err;
    (* keep = "true" *) wire        ila1_soft_err           = soft_err;

    (* keep = "true" *) wire        ila1_user_tx_valid      = user_tx_valid;
    (* keep = "true" *) wire        ila1_user_tx_ready      = user_tx_ready;
    (* keep = "true" *) wire [31:0] ila1_user_tx_data       = user_tx_data;
    (* keep = "true" *) wire        ila1_tx_fire            = user_tx_valid & user_tx_ready;
    (* keep = "true" *) wire [31:0] ila1_tx_last_fire_data  = tx_last_fire_data;
    (* keep = "true" *) wire        ila1_tx_seen_sticky     = tx_seen_sticky;
    (* keep = "true" *) wire [23:0] ila1_tx_cnt             = tx_cnt;

    //==========================================================================
    // 9) ILA2：pixclk 域，统一前缀 ila2_
    //==========================================================================
    (* keep = "true" *) wire        ila2_clk           = pixclk;
    (* keep = "true" *) wire        ila2_pixel_rst_n   = pixel_rst_n;
    (* keep = "true" *) wire        ila2_pll_lock      = pll_lock;
    (* keep = "true" *) wire        ila2_tp_vs         = tp_vs;
    (* keep = "true" *) wire        ila2_tp_hs         = tp_hs;
    (* keep = "true" *) wire        ila2_tp_de         = tp_de;
    (* keep = "true" *) wire [23:0] ila2_tp_rgb        = {tp_r, tp_g, tp_b};

    //==========================================================================
    // 10) ILA3：RX checker / user_clk 域，统一前缀 ila3_
    //     注意：这里故意使用 tx_clk，因为 user_rx_* 就是按 user_clk_i 域来检查。
    //==========================================================================
    (* keep = "true" *) wire        ila3_clk                    = tx_clk;
    (* keep = "true" *) wire        ila3_rx_chk_rst_n           = tx_rst_n;

    (* keep = "true" *) wire        ila3_user_rx_valid          = user_rx_valid;
    (* keep = "true" *) wire [31:0] ila3_user_rx_data           = user_rx_data;
    (* keep = "true" *) wire [31:0] ila3_rx_last_data           = rx_last_data;
    (* keep = "true" *) wire [31:0] ila3_rx_expected_data       = {C_TX_HDR, rx_expected_cnt};
    (* keep = "true" *) wire [31:0] ila3_rx_expected_data_at_err= rx_expected_data_at_err;
    (* keep = "true" *) wire [31:0] ila3_rx_last_error_data     = rx_last_error_data;

    (* keep = "true" *) wire        ila3_rx_seen_sticky         = rx_seen_sticky;
    (* keep = "true" *) wire        ila3_rx_lock_sticky         = rx_lock_sticky;
    (* keep = "true" *) wire        ila3_rx_match_pulse         = rx_match_pulse;
    (* keep = "true" *) wire        ila3_rx_pass_sticky         = rx_pass_sticky;
    (* keep = "true" *) wire        ila3_rx_fail_sticky         = rx_fail_sticky;
    (* keep = "true" *) wire        ila3_rx_mismatch_sticky     = rx_mismatch_sticky;
    (* keep = "true" *) wire        ila3_rx_header_err_sticky   = rx_header_err_sticky;
    (* keep = "true" *) wire        ila3_rx_idle_timeout_sticky = rx_idle_timeout_sticky;
    (* keep = "true" *) wire        ila3_hard_err_sticky        = hard_err_sticky_rx;
    (* keep = "true" *) wire        ila3_soft_err_sticky        = soft_err_sticky_rx;

    (* keep = "true" *) wire [15:0] ila3_rx_good_match_run_cnt  = rx_good_match_run_cnt;
    (* keep = "true" *) wire [31:0] ila3_rx_total_word_cnt      = rx_total_word_cnt;
    (* keep = "true" *) wire [31:0] ila3_rx_good_word_cnt       = rx_good_word_cnt;
    (* keep = "true" *) wire [31:0] ila3_rx_bad_word_cnt        = rx_bad_word_cnt;
    (* keep = "true" *) wire [19:0] ila3_rx_idle_gap_cnt        = rx_idle_gap_cnt;

    //==========================================================================
    // 11) ILA4：原始 PCS 时钟观测点（只给你确认 gt_pcs_rx_clk 是否在跑）
    //==========================================================================
    (* keep = "true" *) wire        ila4_clk               = clk;
    (* keep = "true" *) wire        ila4_pll_lock          = pll_lock;
    (* keep = "true" *) wire        ila4_gt_pll_ok         = gt_pll_ok;
    (* keep = "true" *) wire        ila4_gt_pcs_tx_clk     = gt_pcs_tx_clk;
    (* keep = "true" *) wire        ila4_gt_pcs_rx_clk     = gt_pcs_rx_clk;
    (* keep = "true" *) wire        ila4_channel_up        = channel_up;
    (* keep = "true" *) wire        ila4_lane_up           = lane_up;
    (* keep = "true" *) wire        ila4_gt_rx_align_link  = gt_rx_align_link;
    (* keep = "true" *) wire        ila4_gt_rx_pma_lock    = gt_rx_pma_lock;
    (* keep = "true" *) wire        ila4_gt_rx_k_lock      = gt_rx_k_lock;

endmodule
