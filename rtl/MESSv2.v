// LAB data is read out here now. Scaler data and
// RF power data still come in separately.
module MESSv2( input        clk_i,
	       input 	     cmd_i,
	       input 	     nADS,
	       input 	     WnR,
	       input [7:2]   LA,
	       inout [31:0]  LD,
	       input 	     nCS2,
	       input 	     nCS3,
	       input 	     nRD,
	       output 	     nREADY,
	       output 	     nBTERM,

	       output 	     clr_all_o, 
	       
	       
	       input [31:0]  lab_dat_i,
	       input 	     lab_ready_i,
			 output [3:0] lab_digitize_o,
			 
	       output [12:0] lab_addr_o,
	       input [15:0]  rfp_dat_i,
	       output [4:0]  rfp_addr_o,
	       input [15:0]  dac_dat_i,
	       output [4:0]  dac_addr_o,
	       input [15:0]  scal_dat_i,
	       output [4:0]  scal_addr_o,
			 output [34:0] debug_o
	       );
   wire 		     event_wr;
   wire [31:0] 		     event_id;
   wire [1:0] 		     event_id_buffer;

	// Clears.
   reg 		     clr_all = 0;   
   reg 		     clr_evt = 0;
	
	localparam [31:0] IDENT = "SURF";
	localparam [3:0] VER_MONTH = 7;
	localparam [7:0] VER_DAY = 23;
	localparam [3:0] VER_MAJOR = 3;
	localparam [3:0] VER_MINOR = 8;
	localparam [7:0] VER_REV = 0;
	localparam [3:0] VER_BOARDREV = 0;
   localparam [31:0] VERSION = {VER_BOARDREV,VER_MONTH,VER_DAY,VER_MAJOR,VER_MINOR,VER_REV};
	
   SURF_command_receiver u_receiver(.clk33_i(clk_i),
				    .rst_i(clr_all),
				    .cmd_i(cmd_i),
				    .event_id_wr_o(event_wr),
				    .event_id_buffer_o(event_id_buffer),
				    .event_id_o(event_id),
				    .digitize_o(lab_digitize_o));   

   wire [33:0] 		     event_fifo_in;
	assign event_fifo_in[33:32] = event_id_buffer;
	assign event_fifo_in[31:0] = event_id;
	
   wire [33:0] 		     event_fifo_out;
   wire 		     event_fifo_empty;   
   // The LAB_RAM here uses 3 block RAMs to generate
   // a 3072x16 RAM with a 1536x32 readout port.
   // This means we use 12 block RAMs in total.
   event_fifo u_fifo(.din(event_fifo_in),
		     .dout(event_fifo_out),
		     .clk(clk_i),
		     .wr_en(event_wr),
		     .rd_en(clr_evt),
			  .rst(clr_all),
		     .empty(event_fifo_empty));
   
   // These generate the address outputs for the lab and HK data.
   reg [6:0] 		     hk_counter = {7{1'b0}};
   reg [10:0] 		     lab_counter = {11{1'b0}};   
   
   (* IOB = "TRUE" *)
   reg [5:0] 		     la_q = {6{1'b0}};
   (* IOB = "TRUE" *)
   reg [31:0] 		     ldi_q = {32{1'b0}};
   wire [31:0] 		     ldo_q;
   wire [31:0] 		     ldoeb_q;
   (* IOB = "TRUE" *)
   reg 			     nads_q = 1;
   (* IOB = "TRUE" *)
   reg 			     wnr_q = 1;   
   (* IOB = "TRUE" *)
   reg 			     ncs2_q = 1;
   (* IOB = "TRUE" *)
   reg 			     ncs3_q = 1;
   (* IOB = "TRUE" *)
   reg 			     nready_q = 1;   
   (* IOB = "TRUE" *)
   reg 			     nrd_q = 1;
   
   localparam FSM_BITS = 3;   
   localparam [FSM_BITS-1:0] IDLE = 0;
   localparam [FSM_BITS-1:0] LAB_WR = 1;
   localparam [FSM_BITS-1:0] LAB_RD = 2;
   localparam [FSM_BITS-1:0] HK_WR = 3;
   localparam [FSM_BITS-1:0] HK_RD = 4;
   localparam [FSM_BITS-1:0] REG_WR = 5;
   localparam [FSM_BITS-1:0] REG_RD = 6;
   localparam [FSM_BITS-1:0] LAB_RD_DONE = 7;
   reg [FSM_BITS-1:0] 	     state = IDLE;

   wire [1:0] 		     ldo_in_sel;   
   wire [31:0] 		     ldo_in[3:0];
   wire [31:0] 		     ldo_in_mux;
   wire [31:0] 		     hk_dat_mux;
   // Scalers first, then DAC, then RFP.
   wire [31:0] 		     hk_dat[3:0];
   assign hk_dat[0] = scal_dat_i;
   assign hk_dat[1] = dac_dat_i;
   assign hk_dat[2] = rfp_dat_i;
   assign hk_dat[3] = dac_dat_i;   
   assign hk_dat_mux = hk_dat[hk_counter[6:5]];
   
   wire [31:0] 		     register_data_mux;
   wire [31:0] 		     register_data[7:0];
   assign register_data_mux = register_data[la_q[2:0]];

   assign register_data[0] = IDENT;
   assign register_data[1] = VERSION;
   assign register_data[2] = hk_counter;
   assign register_data[3] = lab_counter;
   assign register_data[4] = {{28{1'b0}},
			      event_fifo_empty,
			      event_fifo_out[33:32],
			      !event_fifo_empty && lab_ready_i };
   assign register_data[5] = event_fifo_out[31:0];
   assign register_data[6] = {{30{1'b0}},clr_evt,clr_all};   
   assign register_data[7] = lab_counter;
   
   wire 		     terminate_read = (state == LAB_RD 
					       || state == HK_RD 
					       || state == REG_RD);   
	// negative logic. If *either* nADSq or nRDq is
	// asserted, keep ready low.
   wire 		     nready_in = nads_q && nrd_q;
   wire 		     ldo_oeb_in = wnr_q && !terminate_read;   
   
   assign nBTERM = 1'b1;   

   always @(posedge clk_i) begin : REGISTER_LOGIC
      if (state == REG_WR) begin
		 if (la_q[2:0] == 3'd2) hk_counter <= ldi_q;
		 if (la_q[2:0] == 3'd3) lab_counter <= ldi_q;
      end      
		if ((state == REG_WR) && la_q[2:0] == 3'd6) clr_all <= ldi_q[0];
		else clr_all <= 0;
		
		if ((state == REG_WR) && la_q[2:0] == 3'd6) clr_evt <= ldi_q[1];
		else clr_evt <= 0;

      // Dumb HK/LAB counter increment. Fix this for bursted reads.
      if (state == HK_RD) hk_counter <= hk_counter + 1;

		if (clr_evt) lab_counter <= {11{1'b0}};
      else if (state == LAB_RD) lab_counter <= lab_counter + 1;      
   end
   
   always @(posedge clk_i) begin : IOB_LOGIC_P
      nads_q <= nADS;
      wnr_q <= WnR;
      ncs2_q <= nCS2;
      ncs3_q <= nCS3;
      ldi_q <= LD;
      la_q <= LA[7:2];      
		nrd_q <= nRD;
	end
	
   always @(negedge clk_i) begin : IOB_LOGIC_N
      nready_q <= nready_in;
   end      
   
   always @(posedge clk_i) begin : FSM_LOGIC
      case (state)
			IDLE: if (!nads_q) begin
				if (wnr_q) begin
					if (!ncs2_q) state <= HK_WR;
					else if (!ncs3_q) state <= LAB_WR;
					else state <= REG_WR;
				end else begin
					if (!ncs2_q) state <= HK_RD;
					else if (!ncs3_q) state <= LAB_RD;
					else state <= REG_RD;
				end
			end // if (!nads_q)
			LAB_WR: state <= IDLE;
			HK_WR: state <= IDLE;
			REG_WR: state <= IDLE;
			LAB_RD: state <= IDLE;
			HK_RD: state <= IDLE;
			REG_RD: state <= IDLE;
			default: state <= IDLE;
      endcase // case (state)
   end // block: FSM_LOGIC
      
   assign ldo_in_sel = {ncs3_q, ncs2_q};
   assign ldo_in[0] = lab_dat_i;
   assign ldo_in[1] = lab_dat_i;
   assign ldo_in[2] = hk_dat_mux;
   assign ldo_in[3] = register_data_mux;
   assign ldo_in_mux = ldo_in[ldo_in_sel];
	
   assign scal_addr_o = hk_counter[4:0];
   assign rfp_addr_o = hk_counter[4:0];
   assign dac_addr_o = hk_counter[4:0];

   assign lab_addr_o = {event_fifo_out[33:32],lab_counter};

   assign clr_all_o = clr_all;
      
   generate
      genvar oe;
      for (oe=0;oe<32;oe=oe+1) begin : LDBUF
			(* IOB = "TRUE" *)
			FD_1 u_ld(.D(ldo_in_mux[oe]),.C(clk_i),.Q(ldo_q[oe]));
			(* IOB = "TRUE" *)
			FD_1 u_ldoe(.D(ldo_oeb_in),.C(clk_i),.Q(ldoeb_q[oe]));
			assign LD[oe] = (ldoeb_q[oe]) ? 1'bZ : ldo_q[oe];
      end
   endgenerate   

	assign nREADY = nready_q;
	
	assign debug_o[0] = nads_q;
	assign debug_o[1] = ncs2_q;
	assign debug_o[2] = ncs3_q;
	assign debug_o[3] = wnr_q;
	assign debug_o[4 +: 3] = state;
	assign debug_o[7] = event_fifo_empty;
	assign debug_o[8] = event_wr;
	assign debug_o[9] = clr_evt;
	assign debug_o[10 +: 4] = la_q[3:0];
	assign debug_o[14 +: 16] = ldi_q[15:0];
	assign debug_o[30] = cmd_i;
	assign debug_o[31] = nrd_q;
	assign debug_o[32] = lab_ready_i;
	assign debug_o[33] = clr_all;
endmodule
