/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//   AHB3-Lite Timer Testbench (Tests)                             //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2017 ROA Logic BV                     //
//             www.roalogic.com                                    //
//                                                                 //
//   This source file may be used and distributed without          //
//   restriction provided that this copyright statement is not     //
//   removed from the file and that any derivative work contains   //
//   the original copyright notice and the associated disclaimer.  //
//                                                                 //
//     This soure file is free software; you can redistribute it   //
//   and/or modify it under the terms of the GNU General Public    //
//   License as published by the Free Software Foundation, either  //
//   version 3 of the License, or (at your option) any later       //
//   versions. The current text of the License can be found at:    //
//   http://www.gnu.org/licenses/gpl.html                          //
//                                                                 //
//    This source file is distributed in the hope that it will be  //
//  useful, but WITHOUT ANY WARRANTY; without even the implied     //
//  warranty of MERCHANTABILITY or FITTNESS FOR A PARTICULAR       //
//  PURPOSE. See the GNU General Public License for more details.  //
//                                                                 //
/////////////////////////////////////////////////////////////////////

module test #(
  parameter TIMERS = 2,       //Number of timers

  parameter HADDR_SIZE = 16,
  parameter HDATA_SIZE = 32
)
(
  input                   HRESETn,
                          HCLK,

  output                  HSEL,
  output [HADDR_SIZE-1:0] HADDR,
  output [HDATA_SIZE-1:0] HWDATA,
  input  [HDATA_SIZE-1:0] HRDATA,
  output                  HWRITE,
  output [           2:0] HSIZE,
  output [           2:0] HBURST,
  output [           3:0] HPROT,
  output [           1:0] HTRANS,
  output                  HMASTLOCK,
  input                   HREADY,
  input                   HRESP,

  input                   tint
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;

  localparam [HADDR_SIZE-1:0] PRESCALE         = 'h0,
                              RESERVED         = 'h4,
                              IPENDING         = 'h8,
                              IENABLE          = 'hc,
                              IPENDING_IENABLE = IPENDING,  //for 64bit access
                              TIME             = 'h10,
                              TIME_MSB         = 'h14,      //for 32bit access
                              TIMECMP          = 'h18,      //address = n*'h08 + 'h18;
                              TIMECMP_MSB      = 'h1c;      //address = n*'h08 + 'h1c;

  localparam PRESCALE_VALUE = 5;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  int reset_watchdog,
      got_reset,
      errors;

  /////////////////////////////////////////////////////////
  //
  // Instantiate the AHB-Master
  //
  ahb3lite_master_bfm #(
    .HADDR_SIZE ( HADDR_SIZE ),
    .HDATA_SIZE ( HDATA_SIZE )
  )
  ahb_mst_bfm (
    .*
  );


  initial
  begin
      errors         = 0;
      reset_watchdog = 0;
      got_reset      = 0;

      forever
      begin
          reset_watchdog++;
          @(posedge HCLK);
          if (!got_reset && reset_watchdog == 1000)
              $fatal(-1,"HRESETn not asserted\nTestbench requires an AHB reset");
      end
  end


  always @(negedge HRESETn)
  begin
      //wait for reset to negate
      @(posedge HRESETn);
      got_reset = 1;

      welcome_text();

      //check initial values
      test_reset_register_values();

      //Test number of timers
      test_ienable_timers();

      //Test registers
      test_registers_rw32();

      //Program prescale register
//      program_prescaler(PRESCALE_VALUE -1); //counts N+1

      //Test Timer0
      test_timer0();

      //Test all timers

      //Finish simulation
      repeat (100) @(posedge HCLK);
      finish_text();
      $finish();
  end


  /////////////////////////////////////////////////////////
  //
  // Tasks
  //
  task welcome_text();
    $display ("------------------------------------------------------------");
    $display (" ,------.                    ,--.                ,--.       ");
    $display (" |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---. ");
    $display (" |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--' ");
    $display (" |  |\\  \\ ' '-' '\\ '-'  |    |  '--.' '-' ' '-' ||  |\\ `--. ");
    $display (" `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---' ");
    $display ("                                           `---'            ");
    $display (" AHB3Lite Timer Testbench Initialized                       ");
    $display (" Timers: %0d                                                ", TIMERS);
    $display ("------------------------------------------------------------");
  endtask : welcome_text


  task finish_text();
    if (errors>0)
    begin
        $display ("------------------------------------------------------------");
        $display (" AHB3Lite Timer Testbench failed with (%0d) errors @%0t", errors, $time);
        $display ("------------------------------------------------------------");
    end
    else
    begin
        $display ("------------------------------------------------------------");
        $display (" AHB3Lite Timer Testbench finished successfully @%0t", $time);
        $display ("------------------------------------------------------------");
    end
  endtask : finish_text


  task test_reset_register_values;
    //all zeros ... why bother
  endtask : test_reset_register_values


  task test_ienable_timers;
    //enable interrupts for all 32 possible timers
    //only the LSBs for the available timers should be '1'

    //create buffer
    logic [HDATA_SIZE-1:0] wbuffer[], rbuffer[];
    wbuffer = new[1];
    rbuffer = new[1];

    $write("Testing amount of timers ... ");
    wbuffer[0] = {HDATA_SIZE{1'b1}};
    ahb_mst_bfm.write(IENABLE, wbuffer, HSIZE_WORD, HBURST_SINGLE); //write all '1's
    ahb_mst_bfm.idle();                                             //wait for HWDATA
    ahb_mst_bfm.read (IENABLE, rbuffer, HSIZE_WORD, HBURST_SINGLE); //read actual value
    wbuffer[0] = {HDATA_SIZE{1'b0}};                                
    ahb_mst_bfm.write(IENABLE, wbuffer, HSIZE_WORD, HBURST_SINGLE); //restore all '0's
    ahb_mst_bfm.idle();                                             //Idle bus
    wait fork;                                                      //wait for all threads to complete

    if (rbuffer[0] !== {TIMERS{1'b1}})
    begin
        errors++;
        $display("FAILED");
        $error("Wrong number of timers. Expected %0d, got %0d", TIMERS, $clog2(rbuffer[0]));
    end
    else
      $display("OK");

    //discard buffers
    rbuffer.delete();
    wbuffer.delete();
  endtask : test_ienable_timers;


  task test_registers_rw32;
    int error,
        hsize,
        hburst,
        n;
    localparam int reg_cnt = 4+ 2*TIMERS;

    logic [HADDR_SIZE-1:0] registers [reg_cnt];
    logic [HDATA_SIZE-1:0] wbuffer[][], rbuffer[][];

    //create list of registers
    for (n=0; n<reg_cnt; n++)
      case (n)
         0: registers[n] = PRESCALE;
         1: registers[n] = IENABLE;
         2: registers[n] = TIME;
         3: registers[n] = TIME_MSB;
         default: registers[n] = (n-4)*'h08 + (n[0] ? TIMECMP_MSB : TIMECMP);
      endcase

    //create buffers
    wbuffer = new[reg_cnt];
    rbuffer = new[reg_cnt];

    $display("Testing registers ... ");
    for (hsize=2; hsize>=0; hsize -= 2)
    begin
        error = 0;
        if (hsize == HSIZE_WORD)
        begin
            hburst = HBURST_SINGLE;
            $write("  Testing word (32bit) accesses ... ");
        end
        else
        begin
            hburst = HBURST_INCR4;
            $write("  Testing byte burst (8bit) accesses ... ");
        end

        for (n=0; n<reg_cnt; n++)
          if (hsize == HSIZE_WORD)
          begin
              wbuffer[n] = new[1];
              rbuffer[n] = new[1];
              wbuffer[n][0] = $random;
          end
          else
          begin
              wbuffer[n] = new[4];
              rbuffer[n] = new[4];
              for (int i=0; i<4; i++)
                wbuffer[n][i] = $random & 'hff;
          end

        for (n=0; n<reg_cnt; n++)
          ahb_mst_bfm.write(registers[n], wbuffer[n], hsize, hburst); //write register

        ahb_mst_bfm.idle();                                           //wait for HWDATA

        for (n=0; n<reg_cnt; n++)
        begin
          ahb_mst_bfm.read (registers[n], rbuffer[n], hsize, hburst); //read register
        end
          

        ahb_mst_bfm.idle();                                           //Idle bus
        wait fork;                                                    //wait for all threads to complete

        for (n=0; n<reg_cnt; n++)
          for (int beat=0; beat<rbuffer[n].size(); beat++)
          begin
              //mask byte ...
              if (HSIZE == HSIZE_BYTE) rbuffer[n][beat] &= 'hff;

              if (n == 1) //IENABLE
              begin
                  wbuffer[n][beat] &= {{32'h0-TIMERS{1'b0}},{TIMERS{1'b1}}};
                  wbuffer[n][beat] >>= 8*beat; 
              end

              if (rbuffer[n][beat] !== wbuffer[n][beat])
              begin
$display ("%0d,%0d: got %x, expected %x", n, beat, rbuffer[n][beat], wbuffer[n][beat]);
                  error = 1;
                  errors++;
              end
          end

        if (error) $display("FAILED");
        else       $display("OK");
    end


    //reset registers to all '0'
    wbuffer[0][0] = 0;
    for (n=0; n<reg_cnt; n++)
      ahb_mst_bfm.write(registers[n], wbuffer[0], HSIZE_WORD, HBURST_SINGLE); //write register


    //discard buffers
    rbuffer.delete();
    wbuffer.delete();
  endtask : test_registers_rw32


  task program_prescaler(input [31:0] value);
    //create buffer
    logic [HDATA_SIZE-1:0] buffer [];
    buffer = new[1];

    //assign buffer
    buffer[0] = value;

    $write("Programming prescaler ... ");
    ahb_mst_bfm.write(PRESCALE, buffer, HSIZE_WORD, HBURST_SINGLE); //write value
    ahb_mst_bfm.idle();                                             //wait for HWDATA
    ahb_mst_bfm.read (PRESCALE, buffer, HSIZE_WORD, HBURST_SINGLE); //read back value
    ahb_mst_bfm.idle();                                             //IDLE bus
    wait fork;

    if (buffer[0] !== value)
    begin
        errors++;
        $display("FAILED");
        $error("Wrong register value. Expected %0d, got %0d", value, buffer[0]);
    end
    else
      $display("OK");

    //discard buffer
    buffer.delete();
  endtask : program_prescaler


  task test_timer0();
    int cnt;
    int timecmp_value = 12;

    //create buffer
    logic [HDATA_SIZE-1:0] buffer [];
    buffer = new[1];

    $display("Testing timer0 ... ");
    $display("  Programming registers ... ");
    buffer[0] = timecmp_value;
    ahb_mst_bfm.write(TIMECMP, buffer, HSIZE_WORD, HBURST_SINGLE);  //write TIMECMP
    buffer[0] = 1;
    ahb_mst_bfm.write(IENABLE, buffer, HSIZE_BYTE, HBURST_SINGLE);  //Enable Timer0-interrupt
    buffer[0] = PRESCALE_VALUE -1;
    ahb_mst_bfm.write(PRESCALE, buffer, HSIZE_WORD, HBURST_SINGLE); //Enable core
    buffer[0] = 0;
    ahb_mst_bfm.write(TIME    , buffer, HSIZE_WORD, HBURST_SINGLE); //write TIME_LSB
    ahb_mst_bfm.write(TIME_MSB, buffer, HSIZE_WORD, HBURST_SINGLE);
    ahb_mst_bfm.idle();                                             //wait for HWDATA
    wait fork;


    //now wait for interrupt to rise
    $write("  Waiting for timer interrupt ... ");
    cnt = 0;
    while (!tint)
    begin
        @(posedge HCLK);

        cnt++; //cnt should start increasing as soon as enable[0]='1'

        if (cnt > 1000) //some watchdog value
        begin
            $display("FAILED");
            $error("Timer interrupt failed");
            break;
        end
    end

    if (tint)
    begin
        $display ("OK");

        //check 'cnt' should be PRESCALE_VALUE * TIMECMP -1
        $write("  Checking time delay ... ");
        if (cnt !== PRESCALE_VALUE * timecmp_value -1)
        begin
            errors++;
            $display("FAILED");
            $error("Wrong time delay. Expected %0d, got %0d", PRESCALE_VALUE * timecmp_value -1, cnt);
        end
        else
          $display("OK");
    end


    //A write to TIMECMP should clear the interrupt
    $write("  Clearing timer interrupt ... ");
    buffer[0] = 1000; //some high number to prevent new interrupts
    ahb_mst_bfm.write(TIMECMP, buffer, HSIZE_WORD, HBURST_SINGLE); //write TIMECMP
    ahb_mst_bfm.idle();

    cnt = 0;
    while (tint)
    begin
        @(posedge HCLK);

        cnt++; //cnt should start increasing as soon as enable[0]='1'

        if (cnt > 1000) //some watchdog value
        begin
            $display("FAILED");
            $error("Clearing interrupt failed");
            break;
        end
    end

    if (!tint)
    begin
        $display ("OK");
    end


    //discard buffer
    buffer.delete();

  endtask : test_timer0

endmodule : test
