
module rgb_2_lvds
(input			rst_n

,input			rgb_clk
,input			rgb_vs
,input			rgb_hs
,input			rgb_de
,input			lvds_eclk
,input	[23:0]	rgb_data

,output lvds_clk_p
,output lvds_clk_n

,output lvds_d0_p
,output lvds_d0_n

,output lvds_d1_p
,output lvds_d1_n

,output lvds_d2_p
,output lvds_d2_n

,output lvds_d3_p
,output lvds_d3_n
);

wire t_DE;
wire t_Hsync;
wire t_Vsync;


wire [23:0] pix_data;
wire [6:0] tx_a ;
wire [6:0] tx_b ;
wire [6:0] tx_c ;
wire [6:0] tx_d ;
wire [6:0] tx_a_inv ;
wire [6:0] tx_b_inv ;
wire [6:0] tx_c_inv ;
wire [6:0] tx_d_inv ;

wire [7:0]	t_R = rgb_data[23:16];
wire [7:0]	t_G = rgb_data[15:8];
wire [7:0]	t_B = rgb_data[7:0];

assign  tx_d = {t_R[6], t_R[7], t_G[6], t_G[7], t_B[6], t_B[7], 1'b1};
assign  tx_c = {t_B[2], t_B[3], t_B[4], t_B[5], rgb_hs, rgb_vs, rgb_de};
assign  tx_b = {t_G[1], t_G[2], t_G[3], t_G[4], t_G[5], t_B[0], t_B[1]};
assign  tx_a = {t_R[0], t_R[1], t_R[2], t_R[3], t_R[4], t_R[5], t_G[0]};

// assign  tx_d_inv = {tx_d[0],tx_d[1],tx_d[2],tx_d[3],tx_d[4],tx_d[5],tx_d[6],tx_d[7]};
// assign  tx_c_inv = {tx_c[0],tx_c[1],tx_c[2],tx_c[3],tx_c[4],tx_c[5],tx_c[6],tx_c[7]};
// assign  tx_b_inv = {tx_b[0],tx_b[1],tx_b[2],tx_b[3],tx_b[4],tx_b[5],tx_b[6],tx_b[7]};
// assign  tx_a_inv = {tx_a[0],tx_a[1],tx_a[2],tx_a[3],tx_a[4],tx_a[5],tx_a[6],tx_a[7]};

wire eclk = lvds_eclk;
wire pix_clk;
/*
lvds_pll lvds_pll
(.reset		(~rst_n)
,.clkin		(rgb_clk) 	//input clkin

,.clkout	(eclk) 		//output clkout
// ,.clkoutp	(pix_clk)
);
*/
LVDS_7_to_1_TX tx_inst
(.RST_Tx   		(~rst_n)

,.eclk     		(eclk)     //PLL
,.sync_clk 		(rgb_clk)//(pix_clk)

,.stop     		(1'b0)

,.T0_in    		(tx_a)     
,.T1_in    		(tx_b)     
,.T2_in    		(tx_c)     
,.T3_in    		(tx_d)

,.TCLK_out_p 	(lvds_clk_p)
,.TCLK_out_n 	(lvds_clk_n)

,.T0_out_p   	(lvds_d0_p)
,.T0_out_n   	(lvds_d0_n)

,.T1_out_p   	(lvds_d1_p)
,.T1_out_n   	(lvds_d1_n)

,.T2_out_p   	(lvds_d2_p)
,.T2_out_n   	(lvds_d2_n)

,.T3_out_p   	(lvds_d3_p)
,.T3_out_n   	(lvds_d3_n)
);

endmodule
