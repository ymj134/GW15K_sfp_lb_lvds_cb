module top(
    input  wire clk,
    input  wire rst_n,
    //output wire sfp_tx_disable,  //板子硬件已经固定接低电平
    output wire led
);

    //assign sfp_tx_disable = 1'b0;

    wire        phy_rx_pcs_clkout;
    wire [87:0] phy_rx_data;
    wire [4:0]  phy_rx_fifo_rdusewd;
    wire        phy_rx_fifo_aempty;
    wire        phy_rx_fifo_empty;
    wire        phy_rx_valid;

    wire        phy_tx_pcs_clkout;
    wire [4:0]  phy_tx_fifo_wrusewd;
    wire        phy_tx_fifo_afull;
    wire        phy_tx_fifo_full;

    wire        phy_refclk;
    wire        phy_signal_detect;
    wire        phy_rx_cdr_lock;
    wire        phy_pll_lock;
    wire        phy_ready;

    wire        phy_rx_clk;
    wire        phy_rx_fifo_rden;
    wire        phy_tx_clk;
    wire [79:0] phy_tx_data;
    wire        phy_tx_fifo_wren;
    wire        phy_pma_rstn;
    wire        phy_pcs_rx_rst;
    wire        phy_pcs_tx_rst;

    assign phy_rx_clk       = phy_rx_pcs_clkout;
    assign phy_tx_clk       = phy_tx_pcs_clkout;
    assign phy_rx_fifo_rden = ~phy_rx_fifo_aempty;
    assign phy_tx_fifo_wren = ~phy_tx_fifo_afull;

    assign phy_pma_rstn     = 1'b1;
    assign phy_pcs_rx_rst   = 1'b0;
    assign phy_pcs_tx_rst   = 1'b0;

    wire [7:0] prbs7_tx_data;
    wire [7:0] prbs7_rx_data;
    wire       prbs7_lock;

    assign phy_tx_data   = {10'b0,10'b0,10'b0,10'b0,10'b0,10'b0,10'b0,{2'b0,prbs7_tx_data}};
    assign prbs7_rx_data = phy_rx_data[7:0];

    prbs7_single_channel #(
        .WIDTH(8)
    ) u_prbs7 (
        .tx_clk_i  (phy_tx_clk),
        .tx_rstn_i (rst_n),
        .tx_en_i   (1'b1),
        .tx_data_o (prbs7_tx_data),

        .rx_clk_i  (phy_rx_clk),
        .rx_rstn_i (phy_rx_cdr_lock),
        .rx_en_i   (1'b1),
        .rx_data_i (prbs7_rx_data),
        .lock_o    (prbs7_lock)
    );

    assign led = prbs7_lock;

    SerDes_Top u_phy (
        .Customized_PHY_Top_q0_ln0_rx_pcs_clkout_o(phy_rx_pcs_clkout),
        .Customized_PHY_Top_q0_ln0_rx_data_o       (phy_rx_data),
        .Customized_PHY_Top_q0_ln0_rx_fifo_rdusewd_o(phy_rx_fifo_rdusewd),
        .Customized_PHY_Top_q0_ln0_rx_fifo_aempty_o(phy_rx_fifo_aempty),
        .Customized_PHY_Top_q0_ln0_rx_fifo_empty_o (phy_rx_fifo_empty),
        .Customized_PHY_Top_q0_ln0_rx_valid_o      (phy_rx_valid),

        .Customized_PHY_Top_q0_ln0_tx_pcs_clkout_o (phy_tx_pcs_clkout),
        .Customized_PHY_Top_q0_ln0_tx_fifo_wrusewd_o(phy_tx_fifo_wrusewd),
        .Customized_PHY_Top_q0_ln0_tx_fifo_afull_o (phy_tx_fifo_afull),
        .Customized_PHY_Top_q0_ln0_tx_fifo_full_o  (phy_tx_fifo_full),

        .Customized_PHY_Top_q0_ln0_refclk_o        (phy_refclk),
        .Customized_PHY_Top_q0_ln0_signal_detect_o (phy_signal_detect),
        .Customized_PHY_Top_q0_ln0_rx_cdr_lock_o   (phy_rx_cdr_lock),
        .Customized_PHY_Top_q0_ln0_pll_lock_o      (phy_pll_lock),
        .Customized_PHY_Top_q0_ln0_ready_o         (phy_ready),

        .Customized_PHY_Top_q0_ln0_rx_clk_i        (phy_rx_clk),
        .Customized_PHY_Top_q0_ln0_rx_fifo_rden_i  (phy_rx_fifo_rden),
        .Customized_PHY_Top_q0_ln0_tx_clk_i        (phy_tx_clk),
        .Customized_PHY_Top_q0_ln0_tx_data_i       (phy_tx_data),
        .Customized_PHY_Top_q0_ln0_tx_fifo_wren_i  (phy_tx_fifo_wren),
        .Customized_PHY_Top_q0_ln0_pma_rstn_i      (phy_pma_rstn),
        .Customized_PHY_Top_q0_ln0_pcs_rx_rst_i    (phy_pcs_rx_rst),
        .Customized_PHY_Top_q0_ln0_pcs_tx_rst_i    (phy_pcs_tx_rst)
    );

endmodule