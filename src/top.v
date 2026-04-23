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
    localparam [31:0] T1S               = 32'd69_999_999;
    localparam [15:0] RX_PREFILL_CYCLES = 16'd1024;

    // 1024x600 timing（沿用你现在点亮的屏参）
    localparam [11:0] C_H_TOTAL  = 12'd1344;
    localparam [11:0] C_H_SYNC   = 12'd24;
    localparam [11:0] C_H_BPORCH = 12'd160;
    localparam [11:0] C_H_RES    = 12'd1024;

    localparam [11:0] C_V_TOTAL  = 12'd635;
    localparam [11:0] C_V_SYNC   = 12'd2;
    localparam [11:0] C_V_BPORCH = 12'd23;
    localparam [11:0] C_V_RES    = 12'd600;

    //==========================================================================
    // 1) LVDS pixel clock
    //==========================================================================
    wire        lvds_eclk;
    wire        pixclk;
    wire        pll_lock;

    Gowin_PLL u_PLL_LVDS_TX
    (
        .clkin      (clk        ),
        .clkout0    (lvds_eclk  ),
        .lock       (pll_lock   ),
        .mdclk      (clk        ),
        .reset      (!rst_n     )
    );

    CLKDIV CLKDIV_inst
    (
        .RESETN     (rst_n      ),
        .HCLKIN     (lvds_eclk  ),
        .CALIB      (1'b0       ),
        .CLKOUT     (pixclk     )
    );
    defparam CLKDIV_inst.DIV_MODE = "3.5";

    // pixel domain reset
    wire pixel_rst;
    wire pixel_rst_n;

    reset_gen u_pixel_reset_gen
    (
        .i_clk1     (pixclk          ),
        .i_lock     (pll_lock & rst_n),
        .o_rst1     (pixel_rst       )
    );

    assign pixel_rst_n = ~pixel_rst;

    //==========================================================================
    // 2) 本地 testpattern
    //==========================================================================
    reg  [31:0] count;
    reg  [2:0]  col_cnt;

    wire [7:0]  tp_r;
    wire [7:0]  tp_g;
    wire [7:0]  tp_b;
    wire        tp_de;
    wire        tp_hs;
    wire        tp_vs;

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
        .I_pxl_clk   (pixclk      ),
        .I_rst_n     (pixel_rst_n ),
        .I_mode      (col_cnt     ),
        .I_single_r  (8'd0        ),
        .I_single_g  (8'd0        ),
        .I_single_b  (8'd255      ),
        .I_h_total   (C_H_TOTAL   ),
        .I_h_sync    (C_H_SYNC    ),
        .I_h_bporch  (C_H_BPORCH  ),
        .I_h_res     (C_H_RES     ),
        .I_v_total   (C_V_TOTAL   ),
        .I_v_sync    (C_V_SYNC    ),
        .I_v_bporch  (C_V_BPORCH  ),
        .I_v_res     (C_V_RES     ),
        .I_hs_pol    (1'b1        ),
        .I_vs_pol    (1'b1        ),
        .O_de        (tp_de       ),
        .O_hs        (tp_hs       ),
        .O_vs        (tp_vs       ),
        .O_data_r    (tp_r        ),
        .O_data_g    (tp_g        ),
        .O_data_b    (tp_b        )
    );

    //==========================================================================
    // 3) TX: packer -> TX FIFO -> SerDes
    //==========================================================================
    wire [31:0] tx_stream_word_data;
    wire        tx_stream_word_valid;
    wire        tx_stream_overflow_sticky;

    wire [35:0] tx_fifo_din;
    wire [35:0] tx_fifo_dout;
    wire        tx_fifo_wr_en;
    wire        tx_fifo_rd_en;
    wire        tx_fifo_empty;
    wire        tx_fifo_full;

    assign tx_fifo_din   = {4'b0000, tx_stream_word_data};
    assign tx_fifo_wr_en = tx_stream_word_valid & (~tx_fifo_full);

    video_symbol_packer_v1 u_video_symbol_packer_v1
    (
        .i_clk              (pixclk                  ),
        .i_rst_n            (pixel_rst_n             ),
        .i_enable           (1'b1                    ),
        .i_vs               (tp_vs                   ),
        .i_hs               (tp_hs                   ),
        .i_de               (tp_de                   ),
        .i_rgb              ({tp_r, tp_g, tp_b}     ),
        .i_word_ready       (~tx_fifo_full           ),
        .o_word_data        (tx_stream_word_data     ),
        .o_word_valid       (tx_stream_word_valid    ),
        .o_overflow_sticky  (tx_stream_overflow_sticky)
    );

    //==========================================================================
    // 4) SerDes user interface / clocks / status
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

    wire        sys_clk;
    wire        sys_rst;
    wire        sys_rst_n;

    wire        gt_reset;
    wire        gt_pcs_tx_reset;
    wire        gt_pcs_rx_reset;

    assign sys_clk          = gt_pcs_tx_clk;
    assign gt_reset         = 1'b0;
    assign gt_pcs_tx_reset  = 1'b0;
    assign gt_pcs_rx_reset  = 1'b0;

    reset_gen u_sys_reset_gen
    (
        .i_clk1     (sys_clk                    ),
        .i_lock     (rst_n & pll_lock & gt_pll_ok),
        .o_rst1     (sys_rst                    )
    );

    assign sys_rst_n = ~sys_rst;

    assign user_tx_data  = tx_fifo_dout[31:0];
    assign user_tx_valid = ~tx_fifo_empty;
    assign tx_fifo_rd_en = user_tx_ready & (~tx_fifo_empty);

    SerDes_Top u_SerDes_Top
    (
        .RoraLink_8B10B_Top_link_reset_o          (link_reset_unused ),
        .RoraLink_8B10B_Top_sys_reset_o           (sys_reset_unused  ),
        .RoraLink_8B10B_Top_user_tx_ready_o       (user_tx_ready     ),
        .RoraLink_8B10B_Top_user_rx_data_o        (user_rx_data      ),
        .RoraLink_8B10B_Top_user_rx_valid_o       (user_rx_valid     ),
        .RoraLink_8B10B_Top_hard_err_o            (hard_err          ),
        .RoraLink_8B10B_Top_soft_err_o            (soft_err          ),
        .RoraLink_8B10B_Top_channel_up_o          (channel_up        ),
        .RoraLink_8B10B_Top_lane_up_o             (lane_up           ),
        .RoraLink_8B10B_Top_gt_pcs_tx_clk_o       (gt_pcs_tx_clk     ),
        .RoraLink_8B10B_Top_gt_pcs_rx_clk_o       (gt_pcs_rx_clk     ),
        .RoraLink_8B10B_Top_gt_pll_lock_o         (gt_pll_ok         ),
        .RoraLink_8B10B_Top_gt_rx_align_link_o    (gt_rx_align_link  ),
        .RoraLink_8B10B_Top_gt_rx_pma_lock_o      (gt_rx_pma_lock    ),
        .RoraLink_8B10B_Top_gt_rx_k_lock_o        (gt_rx_k_lock      ),

        .RoraLink_8B10B_Top_user_clk_i            (sys_clk           ),
        .RoraLink_8B10B_Top_init_clk_i            (clk               ),
        .RoraLink_8B10B_Top_reset_i               (sys_rst           ),
        .RoraLink_8B10B_Top_user_pll_locked_i     (gt_pll_ok         ),
        .RoraLink_8B10B_Top_user_tx_data_i        (user_tx_data      ),
        .RoraLink_8B10B_Top_user_tx_valid_i       (user_tx_valid     ),
        .RoraLink_8B10B_Top_gt_reset_i            (gt_reset          ),
        .RoraLink_8B10B_Top_gt_pcs_tx_reset_i     (gt_pcs_tx_reset   ),
        .RoraLink_8B10B_Top_gt_pcs_rx_reset_i     (gt_pcs_rx_reset   )
    );

    //==========================================================================
    // 5) RX: SerDes -> RX FIFO -> unpacker
    //==========================================================================
    wire [35:0] rx_fifo_din;
    wire [35:0] rx_fifo_dout;
    wire        rx_fifo_wr_en;
    wire        rx_fifo_rd_en;
    wire        rx_fifo_empty;
    wire        rx_fifo_full;

    wire        rx_sym_valid;
    wire        rx_sym_vs;
    wire        rx_sym_hs;
    wire        rx_sym_de;
    wire [23:0] rx_sym_rgb;
    wire        rx_stream_underflow_sticky;

    assign rx_fifo_din   = {4'b0000, user_rx_data};
    assign rx_fifo_wr_en = user_rx_valid & (~rx_fifo_full);

    video_symbol_unpacker_v1 u_video_symbol_unpacker_v1
    (
        .i_clk              (pixclk                     ),
        .i_rst_n            (pixel_rst_n                ),
        .i_fifo_dout        (rx_fifo_dout[31:0]         ),
        .i_fifo_empty       (rx_fifo_empty              ),
        .o_fifo_rd_en       (rx_fifo_rd_en              ),
        .i_video_ready      (rx_read_enable_pclk        ),
        .o_valid            (rx_sym_valid               ),
        .o_vs               (rx_sym_vs                  ),
        .o_hs               (rx_sym_hs                  ),
        .o_de               (rx_sym_de                  ),
        .o_rgb              (rx_sym_rgb                 ),
        .o_underflow_sticky (rx_stream_underflow_sticky )
    );

    //==========================================================================
    // 6) pixel 域：链路同步、RX 预填充、收到 VS 后切显示
    //==========================================================================
    wire fifo_rst;
    assign fifo_rst = (!rst_n) | pixel_rst | sys_rst;

    fifo_top_tx36x4096 u_fifo_top_tx36x4096
    (
        .Data           (tx_fifo_din   ),
        .Reset          (fifo_rst      ),
        .WrClk          (pixclk        ),
        .RdClk          (sys_clk       ),
        .WrEn           (tx_fifo_wr_en ),
        .RdEn           (tx_fifo_rd_en ),
        .Rnum           (             ),
        .Almost_Empty   (             ),
        .Almost_Full    (             ),
        .Q              (tx_fifo_dout  ),
        .Empty          (tx_fifo_empty ),
        .Full           (tx_fifo_full  )
    );

    fifo_top_rx36x4096 u_fifo_top_rx36x4096
    (
        .Data           (rx_fifo_din   ),
        .Reset          (fifo_rst      ),
        .WrClk          (sys_clk       ),
        .RdClk          (pixclk        ),
        .WrEn           (rx_fifo_wr_en ),
        .RdEn           (rx_fifo_rd_en ),
        .Almost_Empty   (             ),
        .Almost_Full    (             ),
        .Q              (rx_fifo_dout  ),
        .Empty          (rx_fifo_empty ),
        .Full           (rx_fifo_full  )
    );

    wire serdes_link_ok;
    assign serdes_link_ok =
        channel_up       &
        lane_up          &
        gt_pll_ok        &
        gt_rx_align_link &
        gt_rx_pma_lock   &
        gt_rx_k_lock;

    reg         link_ok_meta_pclk;
    reg         link_ok_pclk;
    reg         link_ok_pclk_d;
    reg [15:0]  rx_prefill_cnt;
    reg         rx_read_enable_pclk;
    reg         rx_stream_enable_pclk;
    reg         rx_sym_vs_d;

    wire rx_vs_rise_pclk;

    assign rx_vs_rise_pclk = (~rx_sym_vs_d) & rx_sym_vs & rx_sym_valid;

    always @(posedge pixclk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            link_ok_meta_pclk      <= 1'b0;
            link_ok_pclk           <= 1'b0;
            link_ok_pclk_d         <= 1'b0;
            rx_prefill_cnt         <= 16'd0;
            rx_read_enable_pclk    <= 1'b0;
            rx_stream_enable_pclk  <= 1'b0;
            rx_sym_vs_d            <= 1'b0;
        end
        else begin
            link_ok_meta_pclk <= serdes_link_ok;
            link_ok_pclk      <= link_ok_meta_pclk;
            link_ok_pclk_d    <= link_ok_pclk;

            rx_sym_vs_d <= rx_sym_vs;

            if(!link_ok_pclk) begin
                rx_prefill_cnt        <= 16'd0;
                rx_read_enable_pclk   <= 1'b0;
                rx_stream_enable_pclk <= 1'b0;
            end
            else begin
                if(!rx_read_enable_pclk) begin
                    if(rx_prefill_cnt < RX_PREFILL_CYCLES)
                        rx_prefill_cnt <= rx_prefill_cnt + 16'd1;
                    else
                        rx_read_enable_pclk <= 1'b1;
                end

                if(rx_read_enable_pclk && rx_vs_rise_pclk)
                    rx_stream_enable_pclk <= 1'b1;
            end
        end
    end

    //==========================================================================
    // 7) LVDS 输出：未锁流前显示本地蓝底 timing，锁流后显示回环图
    //==========================================================================
    wire        out_vs;
    wire        out_hs;
    wire        out_de;
    wire [23:0] out_rgb;

    assign out_vs  = rx_stream_enable_pclk ? rx_sym_vs  : tp_vs;
    assign out_hs  = rx_stream_enable_pclk ? rx_sym_hs  : tp_hs;
    assign out_de  = rx_stream_enable_pclk ? rx_sym_de  : tp_de;
    assign out_rgb = rx_stream_enable_pclk ? rx_sym_rgb : 24'h00_00_40;

    rgb_2_lvds u_rgb2lvds
    (
        .rst_n      (pixel_rst_n         ),
        .rgb_clk    (pixclk              ),
        .rgb_vs     (out_vs              ),
        .rgb_hs     (out_hs              ),
        .rgb_de     (out_de              ),
        .rgb_data   (out_rgb             ),
        .lvds_eclk  (lvds_eclk           ),

        .lvds_clk_p (lvdsOutClk_p        ),
        .lvds_clk_n (lvdsOutClk_n        ),
        .lvds_d0_p  (lvdsDataOut_p[0]    ),
        .lvds_d0_n  (lvdsDataOut_n[0]    ),
        .lvds_d1_p  (lvdsDataOut_p[1]    ),
        .lvds_d1_n  (lvdsDataOut_n[1]    ),
        .lvds_d2_p  (lvdsDataOut_p[2]    ),
        .lvds_d2_n  (lvdsDataOut_n[2]    ),
        .lvds_d3_p  (lvdsDataOut_p[3]    ),
        .lvds_d3_n  (lvdsDataOut_n[3]    )
    );

    //==========================================================================
    // 8) 单 LED 状态编码
    //    亮灭含义：
    //      灭           : PLL 没起来 / 复位中
    //      慢闪         : LVDS 正常，SerDes 还没 up
    //      快闪         : SerDes up 了，但还没切到 RX 图
    //      常亮         : 已经切到 RX 回环图
    //==========================================================================
    reg [25:0] led_cnt;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            led_cnt <= 26'd0;
        else
            led_cnt <= led_cnt + 26'd1;
    end

    wire led_blink_slow = led_cnt[25];
    wire led_blink_fast = led_cnt[23];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            led <= 1'b0;
        else if(!pll_lock)
            led <= 1'b0;
        else if(!serdes_link_ok)
            led <= led_blink_slow;
        else if(!rx_stream_enable_pclk)
            led <= led_blink_fast;
        else if(hard_err || soft_err || tx_stream_overflow_sticky || rx_stream_underflow_sticky)
            led <= led_blink_fast;
        else
            led <= 1'b1;
    end

endmodule