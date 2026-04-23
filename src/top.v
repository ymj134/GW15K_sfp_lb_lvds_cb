
`define LVDS_TX_CH 4

module top
(
    input 						clk
    ,input 						rst_n
    //.------------      (lvds tx)
    ,output 					lvdsOutClk_p
    ,output 					lvdsOutClk_n
    ,output	[`LVDS_TX_CH-1:0] 	lvdsDataOut_p
    ,output	[`LVDS_TX_CH-1:0] 	lvdsDataOut_n
    //.------------      (output)
    ,output	  reg  				led

);

localparam T1S = 32'd69_999_999;

//==================================LVDS TX====================================
wire        pixclk;
wire        lvds_eclk,pll_lock;  
wire[7:0]   pxl_r,pxl_g,pxl_b;
wire        pxl_de,pxl_hs,pxl_vs;

wire        reset_n;

// clocking
Gowin_PLL u_PLL_LVDS_TX(
    .clkin          (clk        ), //input  clkin
    .clkout0        (lvds_eclk  ), //output  clkout0   175M
    .lock           (pll_lock   ), //output  lock
    .mdclk          (clk        ), //input  mdclk   50M
    .reset          (!rst_n     ) //input  reset
);

CLKDIV CLKDIV_inst
(
    .RESETN(rst_n     ),
    .HCLKIN(lvds_eclk ), //x3.5
    .CALIB (1'b0      ),
    .CLKOUT(pixclk    )  //x1
);
defparam CLKDIV_inst.DIV_MODE = "3.5" ;

assign reset_n = pll_lock;
//------------------------------------------
reg[31:0]  count;
reg[ 2:0]  col_cnt;

always @(posedge clk or negedge rst_n)
begin
	if(!rst_n)
		count[31:0] <= 0;
	else if(count == T1S)
		count[31:0] <= 0;
    else
		count[31:0] <= count[31:0] + 1'b1;
end

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        col_cnt <= 3'b0;
    else if(count == T1S)
    begin
        col_cnt <= col_cnt + 1'b1;
    end
end


always @(posedge clk or negedge rst_n)begin 
  if(!rst_n)begin
      led <= 'd0;
  end 
  else if(count == T1S)begin 
      led <= ~led ;
  end 
end

//------------------------------------------

testpattern testpattern_inst
(
    .I_pxl_clk   (pixclk            ),//pixel clock 
    .I_rst_n     (reset_n           ),//low active 
    .I_mode      (col_cnt           ),//data select
    .I_single_r  (8'd0              ),
    .I_single_g  (8'd0              ),                  //74.25MHz   //83.5MHz    
    .I_single_b  (8'd255            ),                  //1280x720   //1280x800   
    .I_h_total   (12'd1344          ),//hor total time  // 12'd1650  // 12'd1680  
    .I_h_sync    (12'd24            ),//hor sync time   // 12'd40    // 12'd128   
    .I_h_bporch  (12'd160           ),//hor back porch  // 12'd220   // 12'd200   
    .I_h_res     (12'd1024          ),//hor resolution  // 12'd1280  // 12'd1280  
    .I_v_total   (12'd635           ),//ver total time  // 12'd750   // 12'd831   
    .I_v_sync    (12'd2             ),//ver sync time   // 12'd5     // 12'd6     
    .I_v_bporch  (12'd23            ),//ver back porch  // 12'd20    // 12'd22    
    .I_v_res     (12'd600           ),//ver resolution  // 12'd720   // 12'd800   
    .I_hs_pol    (1'b1              ),
    .I_vs_pol    (1'b1              ),
	.O_de        (pxl_de            ),
	.O_hs        (pxl_hs            ),
	.O_vs        (pxl_vs            ),
	.O_data_r    (pxl_r             ),
	.O_data_g    (pxl_g             ),
	.O_data_b    (pxl_b             )
);


// rgb2lvds
rgb_2_lvds	u_rgb2lvds
(
	.rst_n		 (rst_n				), //reset_n

	.rgb_clk    (pixclk			        )	
	,.rgb_vs	 (pxl_vs			    )	
	,.rgb_hs	 (pxl_hs				)	
	,.rgb_de	 (pxl_de				)	
	,.rgb_data   ({pxl_r,pxl_g,pxl_b}	)	
	,.lvds_eclk  (lvds_eclk             )

	,.lvds_clk_p (lvdsOutClk_p			)		
	,.lvds_clk_n (lvdsOutClk_n			)		
	,.lvds_d0_p	 (lvdsDataOut_p[0]      )	
	,.lvds_d0_n	 (lvdsDataOut_n[0]      )	
	,.lvds_d1_p	 (lvdsDataOut_p[1]      )	
	,.lvds_d1_n	 (lvdsDataOut_n[1]      )	
	,.lvds_d2_p	 (lvdsDataOut_p[2]      )	
	,.lvds_d2_n	 (lvdsDataOut_n[2]      )	
	,.lvds_d3_p	 (lvdsDataOut_p[3]      )	
	,.lvds_d3_n	 (lvdsDataOut_n[3]      )	
);



endmodule



