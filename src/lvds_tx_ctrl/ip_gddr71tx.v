`timescale 1ns/1ps
//`define D2CLK
//`define CLK—0
module ip_gddr71tx
(input wire 		reset

,input wire 		sclk
,input wire 		refclk

,input wire [6:0] 	data0
,input wire [6:0] 	data1
,input wire [6:0] 	data2
,input wire [6:0] 	data3

,output wire 		clkout_p
,output wire 		clkout_n

,output wire [3:0] 	dout_p
,output wire [3:0] 	dout_n
);/* synthesis syn_noprune=1 *//* synthesis NGD_DRC_MASK=1 */

wire preamble1_inv;
wire buf_clkout;
wire d0_3;
wire d1_3;
wire d2_3;
wire d3_3;
wire d4_3;
wire d5_3;
wire d6_3;
wire d0_2;
wire d1_2;
wire d2_2;
wire d3_2;
wire d4_2;
wire d5_2;
wire d6_2;
wire d0_1;
wire d1_1;
wire d2_1;
wire d3_1;
wire d4_1;
wire d5_1;
wire d6_1;
wire d0_0;
wire d1_0;
wire d2_0;
wire d3_0;
wire d4_0;
wire d5_0;
wire d6_0;
wire preamble1;
wire scuba_vhi;
wire buf_douto3;
wire buf_douto2;
wire buf_douto1;
wire buf_douto0;
// wire sclk_t;
wire scuba_vlo;
wire eclko;
wire buf_refclk;

INV INV_0 (.I(preamble1), .O(preamble1_inv));


OVIDEO Inst6_ODDR71B (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vhi), 
    .D5(scuba_vhi), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(preamble1), .D0(preamble1), .Q(buf_clkout));
// OVIDEO Inst6_ODDR71B (.PCLK(sclk_t), .FCLK(eclko), .RESET(reset), .D6(scuba_vhi), 
    // .D5(scuba_vhi), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    // .D1(scuba_vhi), .D0(scuba_vhi), .Q(buf_clkout));
`ifdef D2CLK
OVIDEO Inst5_ODDR71B3 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vhi), 
    .D5(scuba_vhi), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(preamble1), .D0(preamble1), .Q(buf_douto3));
OVIDEO Inst5_ODDR71B2 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vhi), 
    .D5(scuba_vhi), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(preamble1), .D0(preamble1), .Q(buf_douto2));
OVIDEO Inst5_ODDR71B1 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vhi), 
    .D5(scuba_vhi), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(preamble1), .D0(preamble1), .Q(buf_douto1));
OVIDEO Inst5_ODDR71B0 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vhi), 
    .D5(scuba_vhi), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(preamble1), .D0(preamble1), .Q(buf_douto0));
`elsif CLK_0
OVIDEO Inst5_ODDR71B3 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vlo), 
    .D5(scuba_vlo), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(scuba_vlo), .D0(scuba_vlo), .Q(buf_douto3));
OVIDEO Inst5_ODDR71B2 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vlo), 
    .D5(scuba_vlo), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(scuba_vlo), .D0(scuba_vlo), .Q(buf_douto2));
OVIDEO Inst5_ODDR71B1 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vlo), 
    .D5(scuba_vlo), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(scuba_vlo), .D0(scuba_vlo), .Q(buf_douto1));
OVIDEO Inst5_ODDR71B0 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(scuba_vlo), 
    .D5(scuba_vlo), .D4(scuba_vlo), .D3(scuba_vlo), .D2(scuba_vlo), 
    .D1(scuba_vlo), .D0(scuba_vlo), .Q(buf_douto0));
`else
OVIDEO Inst5_ODDR71B2 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(d6_2), 
    .D5(d5_2), .D4(d4_2), .D3(d3_2), .D2(d2_2), .D1(d1_2), .D0(d0_2), 
    .Q(buf_douto2));
OVIDEO Inst5_ODDR71B3 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(d6_3), 
    .D5(d5_3), .D4(d4_3), .D3(d3_3), .D2(d2_3), .D1(d1_3), .D0(d0_3), 
    .Q(buf_douto3));
OVIDEO Inst5_ODDR71B1 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(d6_1), 
    .D5(d5_1), .D4(d4_1), .D3(d3_1), .D2(d2_1), .D1(d1_1), .D0(d0_1), 
    .Q(buf_douto1));

OVIDEO Inst5_ODDR71B0 (.PCLK(sclk), .FCLK(eclko), .RESET(reset), .D6(d6_0), 
    .D5(d5_0), .D4(d4_0), .D3(d3_0), .D2(d2_0), .D1(d1_0), .D0(d0_0), 
    .Q(buf_douto0));

`endif

assign scuba_vhi = 1;


DFFR Inst4_FD1S3DX (.D(scuba_vhi), .CLK(sclk), .RESET(reset), .Q(preamble1));
// 
// ELVDS_OBUF Inst7_OB (.O(clkout_p), .OB(clkout_n), .I(buf_clkout));
// ELVDS_OBUF Inst3_OB3 (.O(dout_p[3]), .OB(dout_n[3]), .I(buf_douto3));
// ELVDS_OBUF Inst3_OB2 (.O(dout_p[2]), .OB(dout_n[2]), .I(buf_douto2));
// ELVDS_OBUF Inst3_OB1 (.O(dout_p[1]), .OB(dout_n[1]), .I(buf_douto1));
// ELVDS_OBUF Inst3_OB0 (.O(dout_p[0]), .OB(dout_n[0]), .I(buf_douto0));
 TLVDS_OBUF Inst7_OB (.O(clkout_p), .OB(clkout_n), .I(buf_clkout));
 TLVDS_OBUF Inst3_OB3 (.O(dout_p[3]), .OB(dout_n[3]), .I(buf_douto3));
 TLVDS_OBUF Inst3_OB2 (.O(dout_p[2]), .OB(dout_n[2]), .I(buf_douto2));
 TLVDS_OBUF Inst3_OB1 (.O(dout_p[1]), .OB(dout_n[1]), .I(buf_douto1));
 TLVDS_OBUF Inst3_OB0 (.O(dout_p[0]), .OB(dout_n[0]), .I(buf_douto0));

//assign clkout_p 	= buf_clkout;
//assign dout_p[3]	= buf_douto3;
//assign dout_p[2]	= buf_douto2;
//assign dout_p[1]	= buf_douto1;
//assign dout_p[0]	= buf_douto0;

assign scuba_vlo = 0;

// defparam Inst2_CLKDIVF.DIV_MODE = "3.5" ;
// CLKDIV Inst2_CLKDIVF (.HCLKIN(eclko), .RESETN(~reset), .CALIB(scuba_vlo), 
    // .CLKOUT(sclk_t));

assign eclko = buf_refclk;

// assign sclk = sclk_t;
assign d6_3 = data3[6];
assign d5_3 = data3[5];
assign d4_3 = data3[4];
assign d3_3 = data3[3];
assign d2_3 = data3[2];
assign d1_3 = data3[1];
assign d0_3 = data3[0];
assign d6_2 = data2[6];
assign d5_2 = data2[5];
assign d4_2 = data2[4];
assign d3_2 = data2[3];
assign d2_2 = data2[2];
assign d1_2 = data2[1];
assign d0_2 = data2[0];
assign d6_1 = data1[6];
assign d5_1 = data1[5];
assign d4_1 = data1[4];
assign d3_1 = data1[3];
assign d2_1 = data1[2];
assign d1_1 = data1[1];
assign d0_1 = data1[0];
assign d6_0 = data0[6];
assign d5_0 = data0[5];
assign d4_0 = data0[4];
assign d3_0 = data0[3];
assign d2_0 = data0[2];
assign d1_0 = data0[1];
assign d0_0 = data0[0];
assign buf_refclk = refclk;

endmodule

