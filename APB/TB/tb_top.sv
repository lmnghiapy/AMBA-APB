`timescale 1ns/1ps
module tb_top;
    logic PCLK;
    logic PRESETn;

    logic TRANS;
    logic READ;
    logic WRITE;
    logic [3:0] APB_WRITE_STRB;
    logic [31:0] APB_WRITE_PADDR;
    logic [31:0] APB_WRITE_DATA;
    logic [31:0] APB_READ_PADDR;

    logic [31:0] APB_READ_DATA_OUT;
    logic PREADY;
    logic PSLVERR;

    logic [31:0] read_data;

    integer error_count;

    //Instance APB Top
    APB_Top DUT(
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        
        .TRANS(TRANS),
        .READ(READ),
        .WRITE(WRITE),

        .APB_WRITE_STRB(APB_WRITE_STRB),
        .APB_WRITE_PADDR(APB_WRITE_PADDR),
        .APB_WRITE_DATA(APB_WRITE_DATA),
        .APB_READ_PADDR(APB_READ_PADDR),

        .APB_READ_DATA_OUT(APB_READ_DATA_OUT),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR)
    );

    //Clock generation 100MHZ
    initial begin 
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    //APB Write task
    task automatic apb_write(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [3:0] strb
    );
    begin
        @(negedge PCLK);

        TRANS = 1'b1;
        READ = 1'b0;
        WRITE = 1'b1;

        APB_WRITE_PADDR = addr;
        APB_WRITE_DATA = data;
        APB_WRITE_STRB =strb;
    
        //wait for SETUP phase
        fork
            begin
                wait(DUT.PSELx != 2'b00 && DUT.PENABLE == 1'b0);
            end

            begin
                repeat(20) @(posedge PCLK);
                $fatal(1, "TIMEOUT: Master cannot enter SETUP");
            end

        join_any
        disable fork;

        //Deassert request after entering SETUP
        @(negedge PCLK);
        TRANS = 1'b0;

        //wait until ACCESS completes
        wait(DUT.PENABLE && PREADY);

        if(PSLVERR)
            $display("ERROR: Write error at address %h", addr);
        else
            $display("WRITE: ADDR = %h, DATA = %h, STRB = %h", addr, data, strb);

        //Complete APB Transfer
        @(posedge PCLK);
        @(negedge PCLK);

        READ = 1'b0;
        WRITE = 1'b0;
    end
    endtask

    //APB_READ_TASK
    task automatic apb_read(
        input logic [31:0]  addr,
        output logic [31:0] data
    );
    begin
        @(negedge PCLK);
        TRANS = 1'b1;
        READ =1'b1;
        WRITE = 1'b0;
        APB_READ_PADDR = addr;
        //Wait for setup phase
        wait(DUT.PSELx != 2'b00 && DUT.PENABLE == 1'b0);

        //Deseart request after entering SETUP
        @(negedge PCLK);
        TRANS = 1'b0;

        //Wait until ACCESS completes
        wait(DUT.PENABLE && PREADY);

        // Capture read data before leaving ACCESS
        #1;
        data = APB_READ_DATA_OUT;

        if(PSLVERR) 
            $display("ERROR: Read error at address %h", addr);
        else 
            $display("READ: ADDR = %h, DATA = %h", addr, data);

        @(posedge PCLK);
        @(negedge PCLK);

        READ = 1'b0;
        WRITE =1'b0; 
    end
    endtask


    //Main Test
    initial begin
        error_count = 0;

        TRANS = 0;
        WRITE = 0;
        READ = 0;

        APB_WRITE_STRB = 4'b0000;
        APB_WRITE_PADDR = 32'h0;
        APB_WRITE_DATA = 32'h0;
        APB_READ_PADDR = 32'h0;

        PRESETn = 0;

        $display ("--APB MASTER - 2 SLAVE TEST--");

        //Reset
        repeat (5) @(posedge PCLK);
        @(negedge PCLK);
        PRESETn = 1;

        repeat(2) @(posedge PCLK);

        // Test 1: Write and Read slave 1
        // PADDR[31] = 0;
        $display("\n--TEST 1: SLAVE 1--");

        apb_write(
            32'h0000_0000,
            32'h1234_ABCD,
            4'b1111
        );

        apb_read(
            32'h0000_0000,
            read_data
        );

        if(read_data == 32'h1234_ABCD) begin
            $display("PASS Slave 1 read/write");
        end
        else begin
            $display("FAIL: Slave 1 expected = 1234ABCD, actual = %h", read_data);
            error_count = error_count + 1;
        end

        // Test 2: Write and Read Slave 2
        //PADDR [31] = 1
        $display ("\n--TEST 2: SLAVE 2 --");
        apb_write(
            32'h8000_0000,
            32'h4E474849,
            4'b1111
        );

        apb_read(32'h8000_0000, read_data);
        
        if(read_data == 32'h4E474849) begin
            $display("PASS: Slave 2 read/write");
        end
        else begin
            $display("FAIL: Slave 2 expected = 4E474849, actual = %h", read_data);
            error_count = error_count + 1;
        end

        
        //TEST 3: BYTE Strobe
        $display("\n -- TEST 3: BYTE STROBE -- ");

        //write full word
        apb_write(
            32'h0000_0004,
            32'hAABB_CCDD,
            4'b1111
        );

        //update only byte lane 1
        apb_write (
            32'h0000_0004,
            32'h0000_1100,
            4'b0010
        );

        apb_read(32'h0000_0004, read_data);

        if(read_data === 32'hAABB_11DD) begin
            $display("PASS: Byte strobe");
        end
        else begin
            $display("FAIL Byte strobe expected = AABB11DD, actual = %h", read_data);
            error_count = error_count + 1;
        end

        
        //------------
        //TEST SUMMARY
        $display("\n\n----------------------------");
        if(error_count == 0)
            $display("ALL TESTS PASSED");
        else 
            $display("TEST FAILED: %0d errors", error_count);
        $display("------------------------------");

        #20;
        $finish;
    end

    initial begin
    $monitor(
        "TIME=%0t | STATE=%b | TRANS=%b | READ=%b | WRITE=%b | PSELx=%b | PENABLE=%b | PREADY=%b | PADDR=%h",
        $time,
        DUT.u_master.current_state,
        TRANS,
        READ,
        WRITE,
        DUT.PSELx,
        DUT.PENABLE,
        PREADY,
        DUT.PADDR
    );
    end
endmodule