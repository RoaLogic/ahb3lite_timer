/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Timer                                              //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2017 ROA Logic BV                     //
//             www.roalogic.com                                    //
//                                                                 //
//   Unless specifically agreed in writing, this software is       //
//   licensed under the RoaLogic Non-Commercial License            //
//   version-1.0 (the "License"), a copy of which is included      //
//   with this file or may be found on the RoaLogic website        //
//   http://www.roalogic.com. You may not use the file except      //
//   in compliance with the License.                               //
//                                                                 //
//      THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY          //
//   EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                    //
//   See the License for permissions and limitations under the     //
//   License.                                                      //
//                                                                 //
/////////////////////////////////////////////////////////////////////

// +FHDR -  Semiconductor Reuse Standard File Header Section  -------
// FILE NAME      : ahb3lite_timer.sv
// DEPARTMENT     :
// AUTHOR         : rherveille
// AUTHOR'S EMAIL :
// ------------------------------------------------------------------
// RELEASE HISTORY
// VERSION DATE        AUTHOR      DESCRIPTION
// 1.0     2017-04-24  rherveille  initial release
// ------------------------------------------------------------------
// KEYWORDS : AMBA AHB3-Lite Timer
// ------------------------------------------------------------------
// PURPOSE  : AHB3-Lite Timer
//            Generates one or more timers, compatible with RISC-V
//            software model
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME       RANGE    DESCRIPTION              DEFAULT UNITS
//  HADDR_SIZE       [32,64]  HADDR bus width          32
//  HDATA_SIZE       [32,64]  HWDATA/HRDATA bus width  32
//  TIMERS           1+       no.of timers             3
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : external asynchronous active low; HRESETn
//   Clock Domains       : 1, HCLK, rising edge
//   Critical Timing     :
//   Test Features       : na
//   Asynchronous I/F    : no
//   Scan Methodology    : na
//   Instantiations      : none
//   Synthesizable (y/n) : Yes
//   Other               :                                         
// -FHDR-------------------------------------------------------------



/*
 * address    description                comment
 * 0x0   32   Prescale Register          Global Prescale register
 * 0x8   32   Timer Enable Register      Enable Timers
 * 0xc   32   Interrupt Enable Register  Enable interrupt p. timer
 * 0x10  64   'mtime' Register           'mtime'
 * 0x18  64   'mtimecmp' Register        'mtimecmp'
 */


module ahb3lite_timer #(
  //AHB Parameters
  parameter HADDR_SIZE = 32,
  parameter HDATA_SIZE = 32,

  //Timer Parameters
  parameter TIMERS     = 3    //Number of timers
)
(
  input                       HRESETn,
                              HCLK,

  //AHB Slave Interfaces (receive data from AHB Masters)
  //AHB Masters connect to these ports
  input                       HSEL,
  input      [HADDR_SIZE-1:0] HADDR,
  input      [HDATA_SIZE-1:0] HWDATA,
  output reg [HDATA_SIZE-1:0] HRDATA,
  input                       HWRITE,
  input      [           2:0] HSIZE,
  input      [           2:0] HBURST,
  input      [           3:0] HPROT,
  input      [           1:0] HTRANS,
  output reg                  HREADYOUT,
  input                       HREADY,
  output                      HRESP,

  output reg                  tint  //Timer Interrupt
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;

  localparam BE_SIZE = (HDATA_SIZE+7)/8;

/*
 * address    description                comment
 * 0x0   32   Prescale Register          Global Prescale register
 * 0x4   32   reserved                                         
 * 0x8   32   Interrupt Pending Register Pending interrupt p.timer
 * 0xC   32   Interrupt Enable Register  Enable interrupt p.timer
 * 0x10  64   'time' Register            'time[n]'
 * 0x18  64   'timecmp' Register         'timecmp[n]'
 */

  localparam [HADDR_SIZE-1:0] PRESCALE         = 'h0,
                              RESERVED         = 'h4,
                              IPENDING         = 'h8,
                              IENABLE          = 'hc,
                              IPENDING_IENABLE = IPENDING,  //for 64bit access
                              TIME             = 'h10,
                              TIME_MSB         = 'h14,      //for 32bit access
                              TIMECMP          = 'h18,      //address = n*'h08 + 'h18;
                              TIMECMP_MSB      = 'h1C;      //address = n*'h08 + 'h1C;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //AHB write action
  logic                  ahb_we;
  logic [BE_SIZE   -1:0] ahb_be;
  logic [HADDR_SIZE-1:0] ahb_waddr;

  //Control registers
  //_rd/_wr registers: during writing assume all 32bits are present, but during
  // reading use [TIMERS-1:0]. Synthesis should remove the unused bits (no sink)
  logic             [31:0] prescale_reg,
                           ipending_wr, ipending_rd,
                           ienable_wr,  ienable_rd;
  logic             [63:0] time_reg;
  logic [TIMERS-1:0][63:0] timecmp_reg;
  logic                    enabled,     //first write to PRESCALE enables TIME
                           prescale_wr; //write to PRESCALE registers

  //timer count enable
  logic             [31:0] prescale_cnt;
  logic                    count_enable;

  int idx;


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function logic [6:0] address_offset;
    //returns a mask for the lesser bits of the address
    //meaning bits [  0] for 16bit data
    //             [1:0] for 32bit data
    //             [2:0] for 64bit data
    //etc

    //default value, prevent warnings
    address_offset = 0;
	 
    //What are the lesser bits in HADDR?
    case (HDATA_SIZE)
          1024: address_offset = 7'b111_1111; 
           512: address_offset = 7'b011_1111;
           256: address_offset = 7'b001_1111;
           128: address_offset = 7'b000_1111;
            64: address_offset = 7'b000_0111;
            32: address_offset = 7'b000_0011;
            16: address_offset = 7'b000_0001;
       default: address_offset = 7'b000_0000;
    endcase
  endfunction : address_offset


  function logic [6:0] address_mask;
    //Returns a mask for the major bits of the address
    //meaning bits [HADDR_SIZE-1:0] for 8bits data
    //             [HADDR_SIZE-1:1] for 16bits data
    //             [HADDR_SIZE-1:2] for 32bits data
    //etc
    address_mask = ~address_offset();
  endfunction : address_mask


  function logic [BE_SIZE-1:0] gen_be;
    input [           2:0] hsize;
    input [HADDR_SIZE-1:0] haddr;

    logic [127:0] full_be;
    logic [  6:0] haddr_masked;

    //get number of active lanes for a 1024bit databus (max width) for this HSIZE
    case (hsize)
       HSIZE_B1024: full_be = 'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff; 
       HSIZE_B512 : full_be = 'hffff_ffff_ffff_ffff;
       HSIZE_B256 : full_be = 'hffff_ffff;
       HSIZE_B128 : full_be = 'hffff;
       HSIZE_DWORD: full_be = 'hff;
       HSIZE_WORD : full_be = 'hf;
       HSIZE_HWORD: full_be = 'h3;
       default    : full_be = 'h1;
    endcase

    //generate masked address
    haddr_masked = haddr & address_offset();

    //create byte-enable
    gen_be = full_be[BE_SIZE-1:0] << haddr_masked;
  endfunction : gen_be


  function logic [HDATA_SIZE-1:0] gen_wval;
    //Returns the new value for a register
    // if be[n] == '1' then gen_val[byte_n] = new_val[byte_n]
    // else                 gen_val[byte_n] = old_val[byte_n]
    input [HDATA_SIZE-1:0] old_val,
                           new_val;
    input [BE_SIZE   -1:0] be;

    for (int n=0; n < BE_SIZE; n++)
      gen_wval[n*8 +: 8] = be[n] ? new_val[n*8 +: 8] : old_val[n*8 +: 8];
  endfunction : gen_wval


  function integer timer_idx;
    //Returns the timer index
    input [HADDR_SIZE-1:0] address,  //HADDR
                           offset;   //offset in HADDR space

    timer_idx = address - offset;    //remove offset
    timer_idx >>= 4;                 //MSBs determine index
  endfunction : timer_idx


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * AHB accesses
   */
  //The core supports zero-wait state accesses on all transfers.
  assign HREADYOUT = 1'b1;       //always ready
  assign HRESP     = HRESP_OKAY; //Never an error


  /*
   * AHB Writes
   */
  //generate internal write signal
  always @(posedge HCLK)
    if (HREADY) ahb_we <= HSEL & HWRITE & (HTRANS != HTRANS_BUSY) & (HTRANS != HTRANS_IDLE);
    else        ahb_we <= 1'b0;

  //decode Byte-Enables
  always @(posedge HCLK)
    if (HREADY) ahb_be <= gen_be(HSIZE,HADDR);

  //store write address
  always @(posedge HCLK)
    if (HREADY) ahb_waddr <= HADDR;


  //generate control registers 'read' version
  //synthesis should remove logic for unused bits
  assign ipending_rd = {{32-TIMERS{1'b0}}, ipending_wr[TIMERS-1:0]};
  assign ienable_rd  = {{32-TIMERS{1'b0}}, ienable_wr [TIMERS-1:0]};


  //write registers
generate
  if (HDATA_SIZE == 32)
  begin

      always @(posedge HCLK,negedge HRESETn)
        if (!HRESETn)
        begin
            enabled      <= 1'b0;
            prescale_wr  <= 1'b0;
            prescale_reg <=  'h0;
            ipending_wr  <=  'h0;
            ienable_wr   <=  'h0;
            time_reg     <=  'h0;
            timecmp_reg  <=  'h0;
        end
        else
        begin
            //first normal activity
            prescale_wr <= 1'b0;

            //increment TIME register
            if (count_enable) time_reg <= time_reg +1;

            //check timecmp and set ipending bits
            for (idx=0; idx<TIMERS; idx++)
              ipending_wr[idx] <= enabled & (timecmp_reg[idx] == time_reg);

            //AHB writes overrule normal activity
            if (HREADY && ahb_we)
              case (ahb_waddr & address_mask())
                 PRESCALE: begin
                               prescale_reg <= gen_wval(prescale_reg, HWDATA, ahb_be);
                               enabled      <= 1'b1;
                               prescale_wr  <= 1'b1;
                           end
                 RESERVED: ;
                 IENABLE : ienable_wr   <= gen_wval(ienable_rd,   HWDATA, ahb_be);
                 IPENDING: ;
                 TIME    : time_reg[31: 0] <= gen_wval(time_reg[31: 0], HWDATA, ahb_be);
                 TIME_MSB: time_reg[63:32] <= gen_wval(time_reg[63:32], HWDATA, ahb_be);
                 default : begin //all other addresses are considered 'timecmp'
                               //write timecmp register
                               case (ahb_waddr[2])
                                 1'b0: timecmp_reg[timer_idx(ahb_waddr,TIMECMP)][31: 0] <= gen_wval(timecmp_reg[timer_idx(ahb_waddr,TIMECMP)][31: 0], HWDATA, ahb_be);
                                 1'b1: timecmp_reg[timer_idx(ahb_waddr,TIMECMP)][63:32] <= gen_wval(timecmp_reg[timer_idx(ahb_waddr,TIMECMP)][63:32], HWDATA, ahb_be);
                               endcase

                               //a write to timecmp also clears the interrupt-pending bit
                               ipending_wr[timer_idx(ahb_waddr,TIMECMP)] <= 1'b0; 
                           end
              endcase
        end

  end
  else if (HDATA_SIZE == 64)
  begin

      always @(posedge HCLK,negedge HRESETn)
        if (!HRESETn)
        begin
            enabled      <= 1'b0;
            prescale_wr  <= 1'b0;
            prescale_reg <=  'h0;
            ipending_wr  <=  'h0;
            ienable_wr   <=  'h0;
            time_reg     <=  'h0;
            timecmp_reg  <=  'h0;
        end
        else
        begin
            //first normal activity
            prescale_wr <= 1'b0;

            //increment TIME registers
            if (count_enable) time_reg <= time_reg +1;

            //check timecmp and set ipending bits
            for (idx=0; idx<TIMERS; idx++)
              ipending_wr[idx] <= enabled & (timecmp_reg[idx] == time_reg);

            //AHB writes overrule normal activity
            if (HREADY && ahb_we)
              case (ahb_waddr & address_mask())
                 //PRESCALE+ENABLE
                 PRESCALE        : begin
                                       prescale_reg <= gen_wval({32'h0,prescale_reg}, HWDATA, ahb_be);
                                       enabled      <= 1'b1;
                                       prescale_wr  <= 1'b1;
                                   end
                 IPENDING_IENABLE: ienable_wr   <= gen_wval({32'h0,ienable_rd  }, HWDATA, ahb_be);
                 TIME            : time_reg     <= gen_wval(       time_reg     , HWDATA, ahb_be);
                 default         : begin //all other addresses are considered 'timecmp'
                                       timecmp_reg[timer_idx(ahb_waddr,TIMECMP)] <= gen_wval(timecmp_reg[timer_idx(ahb_waddr,TIMECMP)], HWDATA, ahb_be);

                                       //a write to timecmp also clears the interrupt-pending bit
                                       ipending_wr[timer_idx(ahb_waddr,TIMECMP)] <= 1'b0; 
                                   end
              endcase
        end

  end
endgenerate


  /*
   * AHB Reads
   */
generate
  if (HDATA_SIZE == 32)
  begin

      always @(posedge HCLK)
        case (HADDR & address_mask())
          PRESCALE: HRDATA <= prescale_reg;
          RESERVED: HRDATA <= 32'h0;
          IENABLE : HRDATA <= ienable_rd;
          IPENDING: HRDATA <= ipending_rd;
          TIME    : HRDATA <= time_reg[31: 0];
          TIME_MSB: HRDATA <= time_reg[63:32];
          default : case (HADDR[2])
                      1'b0: HRDATA <= timecmp_reg[timer_idx(HADDR,TIMECMP)][31: 0];
                      1'b1: HRDATA <= timecmp_reg[timer_idx(HADDR,TIMECMP)][63:32];
                    endcase
        endcase

  end
  else if (HDATA_SIZE == 64)
  begin

      always @(posedge HCLK)
        case (HADDR & address_mask())
          PRESCALE        : HRDATA <= {32'h0    ,prescale_reg};
          IPENDING_IENABLE: HRDATA <= {ipending_rd, ienable_rd};
          TIME            : HRDATA <= time_reg;
          default         : HRDATA <= timecmp_reg[timer_idx(HADDR,TIMECMP)];
        endcase

  end
endgenerate


  /*
   * Internals
   */

  //Generate count-enable
  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn                     ) prescale_cnt <= 'h0;
    else if (prescale_wr || ~|prescale_cnt) prescale_cnt <= prescale_reg;
    else                                    prescale_cnt <= prescale_cnt -'h1;

  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn) count_enable <= 1'b0;
    else if (!enabled) count_enable <= 1'b0;
    else               count_enable <= ~|prescale_cnt;


  //Generate interrupt
  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn                     ) tint <= 1'b0;
    else if ( |(ipending_rd & ienable_rd) ) tint <= 1'b1;
    else                                    tint <= 1'b0;
endmodule : ahb3lite_timer
