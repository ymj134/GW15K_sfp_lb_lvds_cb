`timescale 1 ns/ 1 ps
module LVDS_7_to_1_TX 
(input        eclk 
,input        sync_clk   
,input        stop   
,input        RST_Tx                   
,input  [6:0] T0_in   
,input  [6:0] T1_in   
,input  [6:0] T2_in   
,input  [6:0] T3_in                       
,output       TCLK_out_p
,output       TCLK_out_n
,output       T0_out_p  
,output       T1_out_p  
,output       T2_out_p  
,output       T3_out_p    
,output       T0_out_n  
,output       T1_out_n  
,output       T2_out_n  
,output       T3_out_n                                           
);

wire         reset ;
wire   [3:0] tx_do_p ;
wire   [3:0] tx_do_n ;

assign reset = RST_Tx || stop;
      
ip_gddr71tx LVDS_71_Tx 
(.reset      (reset)

,.sclk       (sync_clk)
,.refclk     (eclk)

,.data0      (T0_in)
,.data1      (T1_in)
,.data2      (T2_in)
,.data3      (T3_in)

,.clkout_p	 (TCLK_out_p) 
,.clkout_n	 (TCLK_out_n) 

,.dout_p     (tx_do_p)
,.dout_n     (tx_do_n)
);          

assign T0_out_p = tx_do_p[0];
assign T1_out_p = tx_do_p[1];
assign T2_out_p = tx_do_p[2];
assign T3_out_p = tx_do_p[3];

assign T0_out_n = tx_do_n[0];
assign T1_out_n = tx_do_n[1];
assign T2_out_n = tx_do_n[2];
assign T3_out_n = tx_do_n[3];

endmodule