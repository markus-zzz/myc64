///////////////////////////////////////////////
// Demo SDRAM controller for MT48LC1M16A1 legacy SDRAM
// (C) fpga4fun.com & KNJN LLC 2014

// The MT48LC1M16A1 is a 16Mb SDRAM arranged in 1M x 16bits (using 2 banks)

// This controller feature set has been reduced to make it easy to understand
// It is based on a more complete controller targeted for Xylo-EM and Xylo-LM boards

// Assumptions:
// 1. the SDRAM has been initialized with CAS latency=2, and any valid burst mode
// 2. the read agent is active enough to refresh the RAM (if not, add a refresh timer)

// For more info, check
// http://www.fpga4fun.com/SDRAM.html

///////////////////////////////////////////////

`default_nettype none

module SDRAM_ctrl(
  input clk,
  input rst,

  // read agent
  input RdReq,
  output RdGnt,
  input [19:0] RdAddr,
  output reg [15:0] RdData,
  output RdDataValid,

  // write agent
  input WrReq,
  output WrGnt,
  input [19:0] WrAddr,
  input [15:0] WrData,

  // SDRAM
  output SDRAM_CKE, SDRAM_WEn, SDRAM_CASn, SDRAM_RASn,
  output reg [10:0] SDRAM_A,
  output reg [0:0] SDRAM_BA,
  output reg [1:0] SDRAM_DQM = 2'b11,
  input [15:0] i_SDRAM_DQ,
  output [15:0] o_SDRAM_DQ,
  output reg o_SDRAM_DQ_OE = 1'b0
);

assign SDRAM_CKE = 1'b1;

localparam [2:0] SDRAM_CMD_LOADMODE  = 3'b000;
localparam [2:0] SDRAM_CMD_REFRESH   = 3'b001;
localparam [2:0] SDRAM_CMD_PRECHARGE = 3'b010;
localparam [2:0] SDRAM_CMD_ACTIVE    = 3'b011;
localparam [2:0] SDRAM_CMD_WRITE     = 3'b100;
localparam [2:0] SDRAM_CMD_READ      = 3'b101;
localparam [2:0] SDRAM_CMD_NOP       = 3'b111;

reg [2:0] SDRAM_CMD = SDRAM_CMD_NOP;
assign {SDRAM_RASn, SDRAM_CASn, SDRAM_WEn} = SDRAM_CMD;

// here we decide which of reads or writes have priority
wire read_now  =  RdReq;  // give priority to read requests
wire write_now = ~RdReq & WrReq;  // and if a read is not requested, give writes a chance...

reg [2:0] state=0;
reg ReadSelected=0;  always @(posedge clk) if(state==3'h0) ReadSelected <= read_now;
wire WriteSelected = ~ReadSelected;

wire ReadCycle = (state==3'h0) ? read_now : ReadSelected;
wire [19:0] Addr = ReadCycle ? RdAddr : WrAddr;
reg [19:0] AddrR=0;  always @(posedge clk) AddrR <= Addr;

wire SameRowAndBank = (Addr[19:8]==AddrR[19:8]);
assign RdGnt = (state==3'h0 &  read_now) | (state==3'h1 &  ReadSelected & RdReq & SameRowAndBank);
assign WrGnt = (state==3'h0 & write_now) | (state==3'h1 & WriteSelected & WrReq & SameRowAndBank);

reg [15:0] cntr;
always @(posedge clk) begin
if (rst) begin
  state <= 3'h7;
  cntr <= 16'hffff;
end
else begin
case(state)
  3'h0: begin
    if(RdReq | WrReq) begin  // is there a read or write request?
      SDRAM_CMD <= SDRAM_CMD_ACTIVE;  // if so activate
      SDRAM_BA <= Addr[19];  // this bank
      SDRAM_A <= Addr[18:8];  // this row
      SDRAM_DQM <= 2'b11;
      state <= 3'h1;
    end
    else
    begin
      SDRAM_CMD <= SDRAM_CMD_NOP;  // otherwise stay idle
      SDRAM_BA <= 0;
      SDRAM_A <= 0;
      SDRAM_DQM <= 2'b11;
      state <= 3'h0;
    end
  end
  3'h1: begin
    SDRAM_CMD <= ReadSelected ? SDRAM_CMD_READ : SDRAM_CMD_WRITE;
    SDRAM_BA <= AddrR[19];
    SDRAM_A[9:0] <= {2'b00, AddrR[7:0]};  // column
    SDRAM_A[10] <= 1'b0;  // no auto-precharge
    SDRAM_DQM <= 2'b00;
    state <= (ReadSelected ? RdReq : WrReq) & SameRowAndBank ? 3'h1 : 3'h2;
  end
  3'h2: begin
    SDRAM_CMD <= SDRAM_CMD_PRECHARGE;  // close the row when we're done with it
    SDRAM_BA <= 0;
    SDRAM_A <= 11'b100_0000_0000;  // all banks precharge
    SDRAM_DQM <= 2'b11;
    state <= 3'h0;
  end
  3'h3: begin
    SDRAM_CMD <= SDRAM_CMD_NOP;
    SDRAM_BA <= 0;
    SDRAM_A <= 0;
    SDRAM_DQM <= 2'b11;
    state <= 3'h0;
  end

  3'h7: begin
    cntr <= cntr - 1;
    SDRAM_CMD <= SDRAM_CMD_NOP;
    if (cntr == 0) begin
      SDRAM_CMD <= SDRAM_CMD_LOADMODE;
      SDRAM_A <= 13'b000_0_00_010_0_000;
      state <= 3'h6;
      cntr <= 16'hffff;
    end
  end
  3'h6: begin
    cntr <= cntr - 1;
    SDRAM_CMD <= SDRAM_CMD_NOP;
    if (cntr == 0) begin
      state <= 3'h0;
    end
  end
endcase
end
end

localparam trl = 4;  // total read latency is the SDRAM CAS-latency (two) plus the SDRAM controller induced latency (two)
reg [trl-1:0] RdDataValidPipe;  always @(posedge clk) RdDataValidPipe <= {RdDataValidPipe[trl-2:0], state==3'h1 & ReadSelected};
assign RdDataValid = RdDataValidPipe[trl-1];
always @(posedge clk) RdData <= i_SDRAM_DQ;

always @(posedge clk) o_SDRAM_DQ_OE <= (state==3'h1) & WriteSelected;
reg [15:0] WrData1=0;  always @(posedge clk) WrData1 <= WrData;
reg [15:0] WrData2=0;  always @(posedge clk) WrData2 <= WrData1;

assign o_SDRAM_DQ = WrData2;
endmodule
///////////////////////////////////////////////
