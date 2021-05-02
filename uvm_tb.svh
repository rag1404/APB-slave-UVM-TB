//FIXME Need to complete Assertions in the Interface 

import uvm_pkg::*;

`include "uvm_macros.svh"

typedef enum {READ, WRITE} kind_e;

//apb_rw sequence item derived from base uvm_sequence_item
class apb_rw extends uvm_sequence_item;
 
   //typedef for READ/Write transaction type
  
  rand bit   [7:0] addr;      //Address
  rand logic [31:0] pwdata;
  bit [31:0] prdata;//Data - For write or read response
  rand kind_e  apb_cmd;       //command type
  rand logic [3:0] pstrb;
    //Register with factory for dynamic creation
   `uvm_object_utils(apb_rw)
  
   
   function new (string name = "apb_rw");
      super.new(name);
   endfunction

   function string convert2string();
     return $psprintf("kind=%s addr=%0h wdata=%0h rdata=%0h",apb_cmd,addr,pwdata,prdata);
   endfunction
  
  

endclass: apb_rw



class apb_sequencer extends uvm_sequencer #(apb_rw);

   `uvm_component_utils(apb_sequencer)
 
   function new(input string name, uvm_component parent=null);
      super.new(name, parent);
   endfunction : new

endclass : apb_sequencer

class apb_config extends uvm_object;

   `uvm_object_utils(apb_config)
   virtual apb_if vif;

  function new(string name="apb_config");
     super.new(name);
  endfunction

endclass





class apb_base_seq extends uvm_sequence#(apb_rw);
  
  bit [7:0] addrque[$];
  bit [7:0] addrfrom;
  `uvm_object_utils(apb_base_seq)

  function new(string name ="");
    super.new(name);
  endfunction


  
  task body();
     apb_rw write_trans,read_trans;
    
     repeat(10) begin
       write_trans = apb_rw::type_id::create(.name("write_tans"),.contxt(get_full_name()));
       start_item(write_trans);
       if (!write_trans.randomize() with {write_trans.apb_cmd==WRITE;}) begin
         `uvm_error ("body", "Randomization failed");
       end
       addrque.push_back(write_trans.addr);
       `uvm_info ("Inside_seq",$sformatf("write addr = %h",write_trans.addr),UVM_MEDIUM);
       finish_item(write_trans);
     end
       
     repeat (10) begin
     
         start_item(write_trans);
         addrfrom = addrque.pop_front();
         if (!write_trans.randomize() with {write_trans.apb_cmd==READ;addr == addrfrom;}) begin
         `uvm_error ("body", "Randomization failed");
       end
         `uvm_info("Inside_seq" ,$sformatf("Read addr = %h",write_trans.addr),UVM_MEDIUM);
         finish_item(write_trans);
       end
  endtask
  
endclass





class apb_master_drv extends uvm_driver#(apb_rw);
  
  `uvm_component_utils(apb_master_drv)
   
   virtual apb_if vif;
   apb_config cfg;
  
  
  bit ss_sel;

   function new(string name,uvm_component parent = null);
      super.new(name,parent);
     
   endfunction

  
   function void build_phase(uvm_phase phase);
   //  apb_agent agent;
     super.build_phase(phase);
   
         if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("APB/DRV/NOVIF", "No virtual interface specified for this driver instance")
        
     end
   endfunction

   
   virtual task run_phase(uvm_phase phase);
     super.run_phase(phase);
    
     vif.psel    <= '0;
     vif.penable <= '0;

     forever begin
       apb_rw tr;
       
       if (!vif.rst_n) begin
      
         vif.pwdata <=0;
         vif.paddr <= 0;
         vif.pwrite <=0;
       //  vif.hsize <= 0;
       //  vif.htrans <= 0;
         vif.psel <=0;
         vif.pstrb <=0;
         
       end
       
       
       @ (posedge vif.pclk);
       //First get an item from sequencer
       seq_item_port.get_next_item(tr);
       @ (posedge vif.pclk);
       uvm_report_info("APB_DRIVER ", $psprintf("Got Transaction %s",tr.convert2string()));
       //Decode the APB Command and call either the read/write function
       case (tr.apb_cmd)
         READ:  drive_read(tr.addr, tr.prdata);  
         WRITE: drive_write(tr.addr, tr.pwdata,tr.pstrb);
       endcase
     //  ev1.trigger();
       //Handshake DONE back to sequencer
       
       
       seq_item_port.item_done();
     end
   endtask: run_phase

   virtual protected task drive_read(input  bit   [31:0] addr,
                                     output logic [31:0] prdata);
     vif.paddr   <= addr;
     vif.pwrite  <= '0;
     vif.psel    <= '1;
     vif.pstrb <= 4'b0;
     @ (posedge vif.pclk);
     vif.penable <= '1;
     while (vif.pready ==1);
     @ (posedge vif.pclk);
     prdata = vif.prdata;
     @(posedge vif.pclk);
     vif.psel    <= '0;
     vif.penable <= '0;
   endtask: drive_read

   virtual protected task drive_write(input bit [31:0] addr,
                                      input bit [31:0] pwdata, input bit [3:0] pstrb);
      vif.paddr   <= addr;
      vif.pstrb <= pstrb;
      
     
     for (int i=0; i<=3; i++) begin
       ss_sel = pstrb >> i;
       `uvm_info ("Driver",$sformatf("Shift select value is %b , Pstrb value is %b",ss_sel,pstrb),UVM_LOW);  
       vif.pwdata[8*i+:8] <= ss_sel ? pwdata [8*i+:8] : 'h00; 
     end 
      vif.pwrite  <= '1;
      vif.psel    <= '1;
     @ (posedge vif.pclk);
      vif.penable <='1;
     while (vif.pready ==1);
    
     @ (posedge vif.pclk);
      vif.psel    <= '0;
      vif.penable <= '0;
      vif.pwrite <= '0;
   endtask: drive_write

endclass: apb_master_drv

typedef apb_config;
typedef apb_agent;

class apb_monitor extends uvm_monitor;

 virtual apb_if vif;
 
  uvm_analysis_port#(apb_rw) ap;

  //config class handle
  apb_config cfg;
   kind_e kind;

  `uvm_component_utils(apb_monitor)

   function new(string name, uvm_component parent = null);
     super.new(name, parent);
     ap = new("ap", this);
     
   endfunction: new

   //Build Phase - Get handle to virtual if from agent/config_db
   virtual function void build_phase(uvm_phase phase);
    apb_agent agent;
     if ($cast(agent, get_parent()) && agent != null) begin
       vif = agent.vif;
    end
     else begin
       virtual apb_if tmp;
       if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_if", tmp)) begin
         `uvm_fatal("APB/MON/NOVIF", "No virtual interface specified for this monitor instance")
       end
      vif = tmp;
   end
   endfunction

   virtual task run_phase(uvm_phase phase);
     apb_rw tr;
     super.run_phase(phase);
    // @(posedge vif.pclk);
     forever begin
       @(posedge vif.pclk);
       // Wait for a SETUP cycle
       //if (vif.psel) begin
       //@(posedge vif.pclk);
         //create a transaction object
       if((vif.pwrite) || (!vif.pwrite)) begin
       tr = apb_rw::type_id::create("tr");
       //  tr.addr = vif.paddr;
         
       //@(posedge vif.pclk) 
        tr.apb_cmd =vif.pwrite? WRITE:READ;
        tr.addr = vif.paddr;
        tr.prdata = vif.prdata;
        tr.pwdata = vif.pwdata;
        tr.pstrb  = vif.pstrb; 
         `uvm_info ("Monitor",$sformatf("wdata = %h, prdata = %h, paddr = %h  pstrb = %h",tr.pwdata,tr.prdata,tr.addr,tr.pstrb),UVM_LOW); 
       ap.write(tr);
       end
      end
   endtask: run_phase

endclass: apb_monitor


class apb_coverage extends uvm_subscriber#(apb_rw);
  `uvm_component_utils (apb_coverage)
  
 
     
  covergroup read_write with function sample(kind_e);
  option.per_instance=1;
  //type_option.merge_instances=1;
  READ_WRITE: coverpoint trans.apb_cmd {
    bins apb_cmd [] = {[0:1]};
  }
 endgroup
  
  covergroup pstrb_cov ();
    option.per_instance=1;
    //option.name = myname;
    PSTRB : coverpoint trans.pstrb {
    
     wildcard bins pstrb_0 =  {4'b0001};
      wildcard bins pstrb_1 =  {4'b001?};
      wildcard bins pstrb_2 = {4'b01??};
     wildcard  bins pstrb_3 = {4'b1???};
    }
  endgroup
  
  
  function new (string name = "apb_coverage", uvm_component parent);
    super.new(name,parent);
    read_write = new();
    pstrb_cov = new();
  endfunction
  
   function void build_phase(uvm_phase phase);
   //  apb_agent agent;
     super.build_phase(phase);
    
     
   endfunction

   //Run Phase
    // Assume comp_a has original transaction
    apb_rw trans;
  function void write(apb_rw t);
   trans = t;
   read_write.sample(trans.apb_cmd);
    
    pstrb_cov.sample();
  endfunction
  
  

  function void check_phase (uvm_phase phase);
    super.check_phase(phase);
    `uvm_info("Coverage_info",$sformatf("Coverage = %0.2f %%",read_write.get_coverage()),UVM_MEDIUM);
    `uvm_info("Coverage_info",$sformatf("Coverage = %0.2f %%",pstrb_cov.get_coverage()),UVM_MEDIUM);
  endfunction

endclass


typedef apb_config;
typedef apb_agent;




class apb_agent extends uvm_agent;

   //Agent will have the sequencer, driver and monitor components for the APB interface
   apb_sequencer sqr;
   apb_master_drv drv;
   apb_monitor mon;
   apb_coverage cov;
  uvm_analysis_port#(apb_rw) ap_agt;

  virtual apb_if  vif;

   `uvm_component_utils_begin(apb_agent)
      `uvm_field_object(sqr, UVM_ALL_ON)
      `uvm_field_object(drv, UVM_ALL_ON)
      `uvm_field_object(mon, UVM_ALL_ON)
   `uvm_component_utils_end
   
   function new(string name, uvm_component parent = null);
      super.new(name, parent);
     ap_agt = new("ap_agt", this);
   endfunction

   //Build phase of agent - construct sequencer, driver and monitor
   //get handle to virtual interface from env (parent) config_db
   //and pass handle down to srq/driver/monitor
   virtual function void build_phase(uvm_phase phase);
      sqr = apb_sequencer::type_id::create("sqr", this);
      drv = apb_master_drv::type_id::create("drv", this);
      mon = apb_monitor::type_id::create("mon", this);
     cov = apb_coverage::type_id::create("cov", this);
      
      if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
         `uvm_fatal("APB/AGT/NOVIF", "No virtual interface specified for this agent instance")
      end
     uvm_config_db#(virtual apb_if)::set( this, "sqr", "vif", vif);
     uvm_config_db#(virtual apb_if)::set( this, "drv", "vif", vif);
     uvm_config_db#(virtual apb_if)::set( this, "mon", "vif", vif);
   endfunction: build_phase

   //Connect - driver and sequencer port to export
   virtual function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      uvm_report_info("apb_agent::", "connect_phase, Connected driver to sequencer");
     mon.ap.connect(ap_agt);
     mon.ap.connect(cov.analysis_export);
   endfunction
endclass: apb_agent




class apb_scoreboard extends uvm_subscriber#(apb_rw);
  `uvm_component_utils (apb_scoreboard)
  
     virtual apb_if vif;

  
    
    // Associative array holding the transactions from two sources comp_a and comp_b indexed through id field.
  bit[31:0] mem[bit[7:0]];
 
  
    int match;
    int no_match;
   
  //uvm_analysis_port#(apb_rw) ap_scb;
  function new (string name = "apb_scoreboard", uvm_component parent);
    super.new(name,parent);
  //  ap_scb = new ("ap_scb",this);
  endfunction
  
   function void build_phase(uvm_phase phase);
   //  apb_agent agent;
     super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
          `uvm_fatal("APB/DRV/NOVIF", "No virtual interface specified for this scb instance")
      end
   endfunction

   //Run Phase
    // Assume comp_a has original transaction
  
  function void write(apb_rw t);
    if (vif.pwrite) mem[t.addr] = t.pwdata;
   // debug();
     if (!vif.pwrite) begin
      if (mem.exists(t.addr)) begin
        if (mem[t.addr] == t.prdata) 
          begin match++;
        `uvm_info ("Scoreboard", $sformatf("The received transaction in scoreboard wdata = %h, addr = %h, prdata = %h, match = %h ",t.pwdata,t.addr,t.prdata,match),UVM_LOW);
            mem.delete(t.addr);
        end
    end
    end
    
  endfunction
  
  function void debug();
    foreach (mem[i]) begin
      `uvm_info ("Scb",$sformatf ("Debug prints for addr = %h , pdata = %h",i,mem[i]),UVM_LOW);
    end
  endfunction

  function void check_phase (uvm_phase phase);
    super.check_phase(phase);
    debug();
    if (match != 10) begin
      `uvm_error ("Scoreboard",$sformatf ("No of writes issued didnt match no of reads")); end
    else begin`uvm_info ("Scoreboard",$sformatf ("******** TEST PASSED ********"),UVM_MEDIUM); end
  endfunction

endclass


//----------------------------------------------
// APB Env class
//----------------------------------------------
class apb_env  extends uvm_env;
 
   `uvm_component_utils(apb_env);

   //ENV class will have agent as its sub component
   apb_agent  agt;
   apb_scoreboard scb;
 
   //virtual interface for APB interface
   virtual apb_if  vif;

   function new(string name, uvm_component parent = null);
      super.new(name, parent);
   endfunction

   //Build phase - Construct agent and get virtual interface handle from test  and pass it down to agent
   function void build_phase(uvm_phase phase);
     agt = apb_agent::type_id::create("agt", this);
     scb = apb_scoreboard::type_id::create("scb",this);
     if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
         `uvm_fatal("APB/AGT/NOVIF", "No virtual interface specified for this env instance")
     end
     uvm_config_db#(virtual apb_if)::set( this, "agt", "vif", vif);
     uvm_config_db#(virtual apb_if)::set( this, "scb", "vif", vif);
     
   endfunction: build_phase
  
    virtual function void connect_phase(uvm_phase phase);
      
      agt.ap_agt.connect(scb.analysis_export);
   endfunction
//endclass: apb_agent
  
endclass : apb_env  
  

  module test;

   logic pclk;
  
  
  initial begin
    $dumpvars(0,test);
    $dumpfile ("dump.vcd");
    
  end
  
   initial begin
      pclk=0;
      apb_if.rst_n=0;
      #10 apb_if.rst_n=1;
   end

    //Generate a clock
   always begin
      #10 pclk = ~pclk;
   end
 
    
  //  apb_if abp_if (.*);
   //Instantiate a physical interface for APB interface
    apb_if  apb_if(.*,.pclk(pclk));
  apb_slave d1 (.pclk(apb_if.pclk),.rst_n(apb_if.rst_n),.paddr(apb_if.paddr),.pwrite(apb_if.pwrite),.psel(apb_if.psel),.penable(apb_if.penable),.pwdata(apb_if.pwdata),.prdata(apb_if.prdata),.pready(apb_if.pready),.pstrb(apb_if.pstrb));
  
  initial begin
    //Pass this physical interface to test top (which will further pass it down to env->agent->drv/sqr/mon
    uvm_config_db#(virtual apb_if)::set( null, "uvm_test_top", "vif", apb_if);
    //Call the test - but passing run_test argument as test class name
    //Another option is to not pass any test argument and use +UVM_TEST on command line to sepecify which test to run
    run_test("apb_base_test");
  end
  
  
endmodule

//------------------------------------
//APB (Advanced peripheral Bus) Interface 
//


interface apb_if(input bit pclk);
  logic [7:0] paddr;
  logic        psel;
  logic         penable;
  logic        pwrite;
  logic [31:0] prdata;
  logic [31:0] pwdata;
  logic rst_n;
  logic pready;
  logic now_waite_write =0;
  logic [3:0] pstrb;
    

   //Master Clocking block - used for Drivers
  
// Check for X or Z
  
  property apwrite;
    @(posedge pclk) disable iff (!rst_n) 
    !$isunknown(pwrite);
  endproperty
  
  unknown_pwrite: assert property (apwrite) else begin
    `uvm_error ("$isunknown",$sformatf("pwrite has x or z"));
  end
  
    property apsel;
    @(posedge pclk) disable iff (!rst_n) 
      !$isunknown(psel);
  endproperty
  
    unknown_psel: assert property (apsel) else begin
      `uvm_error ("$isunknown",$sformatf("psel has x or z"));
  end
  
       property apenable;
    @(posedge pclk) disable iff (!rst_n) 
         !$isunknown(penable);
  endproperty
  
      unknown_penable: assert property (apenable) else begin
        `uvm_error ("$isunknown",$sformatf("pnable has x or z"));
  end
    
        
         property apstrb;
    @(posedge pclk) disable iff (!rst_n) 
           !$isunknown(pstrb);
  endproperty
  
        unknown_pstrb: assert property (apstrb) else begin
          `uvm_error ("$isunknown",$sformatf("pstrb has x or z"));
  end
    
  property pstrb_read;
    @(posedge pclk) disable iff (!rst_n)
    (!pwrite) and (prdata!=0)|-> (!pwrite throughout (pstrb==4'b0));
  endproperty
          
          apstrb_read: assert property (pstrb_read) else begin
            `uvm_error ("$apstrb_read",$sformatf("pstrb is not 0 during read"));
  end
            
    property pstrb_write;
      bit [3:0] local_strb;
      int v=0;
      bit ss_sel;
      @(posedge pclk) disable iff (!rst_n)
      ($rose(pwrite),local_strb=pstrb,$display ("pstrb value is %b and pwdata %h",pstrb,pwdata)) ##1 (v<4,ss_sel=pstrb>>v,v=v+1,$display("ss_sel value is %b",ss_sel))[=4];
    endproperty
            
            apstrb_write: assert property (pstrb_write);        
      
      
         //   for (int i=0; i<=3; i++) begin
       //ss_sel = pstrb >> i;
  //vif.pwdata[8*i+:8] <= ss_sel ? pwdata [8*i+:8] : 'h00;           
        
  property p_write;
           @(posedge pclk) now_waite_write ##0  
              $rose (pwrite && psel) |->  ##1   // 1 $rose is at T2 
  $stable(paddr) && $stable(pwdata) ##0    // 2 at T3
              // addr@T2 == addr@T3, i.e., thus stable 
              $rose (penable && pready) ##1                  // 3  at $rose at T3
              pwrite && !psel && !penable;       
endproperty 
  //assert property (p_write) $display ("Assertion passed",$time);
    
    
sequence setup_phase_write;
   $rose(psel) and $rose(pwrite) and (!pready) and (!penable);
endsequence 
  
  sequence access_phase_write;
    $rose (penable) and $rose (pready) and $stable (psel) and $stable (pwrite) and $stable (paddr) and $stable (pwdata);
  endsequence 
  
  
  sequence setup_phase_read;
   // @(posedge pclk) disable iff (!rst_n)
    $rose(psel) and (!pwrite) and (!pready) and (!penable);
  endsequence 
  
  sequence access_phase_read;
   //@(posedge pclk) disable iff (!rst_n)
    $rose (penable) and $rose (pready) and $stable (psel) and $stable (!pwrite) and $stable (paddr);
  endsequence 
  
  property data_check;
    int local_addr,local_data;
    @(posedge pclk) disable iff (!rst_n)
    ($rose(pwrite),local_data=pwdata,$display ("local_data value is %h",local_data)) |-> strong (first_match (##[1:$] (prdata==local_data)));
  endproperty
  
   property addr_data_check;
    int local_addr,local_data;
    @(posedge pclk) disable iff (!rst_n)
     ($rose(pwrite),local_addr=paddr,$display ("local addr is %h",local_addr)) |-> strong (##1 (1,local_data=pwdata,$display ("Local Data is %h",local_data)) ##0 first_match (##[1:$] (local_addr==paddr,$display ("paddr value is %h",paddr))) ##1 first_match (##[1:$] (prdata==local_data,$display("prdata is %h",prdata)))) ;
  endproperty
    
 apdata_check: assert property (data_check) 
    begin $display ("Assertion passed with data check",$time); end 
    else 
      begin `uvm_error ("Assertion Failure",$sformatf ("Assertion failed with  , paddr: %h, prdata %h,",$sampled(paddr),$sampled(prdata))); 
     end
  
   aaddr_data_check: assert property (addr_data_check) 
      begin $display ("Assertion passed with addr and data check",$time); end 
    else 
      begin `uvm_error ("Assertion Failure",$sformatf ("Assertion failed with  , paddr: %h, prdata %h,",$sampled(paddr),$sampled(prdata))); 
     end
  
    
   property apb_test_read;
    @(posedge pclk) disable iff (!rst_n) 
    setup_phase_read |-> ##1 access_phase_read;
  endproperty
  
  assert property (apb_test_read) 
    begin $display ("Assertion passed with setup and access phase read",$time); end 
    else 
      begin `uvm_error ("Assertion Failure",$sformatf ("Assertion failed with psel value : %b, pwrite value : %b, pready value : %b, penable value %b , paddr: %h, prdata %h,",$sampled(psel),$sampled(pwrite),$sampled(pready),$sampled(penable),$sampled(paddr),$sampled(prdata))); 
     end
    
    
    
    
    
  property apb_test;
    @(posedge pclk) disable iff (!rst_n) 
    setup_phase_write |-> ##1 access_phase_write;
  endproperty
  
  assert property (apb_test) 
  begin $display ("Assertion passed with setup and access_phase",$time); end 
    else 
      begin `uvm_error ("Assertion Failure",$sformatf ("Assertion failed with psel value : %b, pwrite value : %b, pready value : %b, penable value %b, paddr value : %b, pwdata value %b", $sampled(psel),$sampled(pwrite),$sampled(pready),$sampled(penable),$sampled(paddr),$sampled(pwdata))); 
     end
    
    
  /*  property apb_test_read;
    @(posedge pclk) disable iff (!rst_n) 
    setup_phase_read |-> ##1 access_phase_read;
  endproperty
  
    assert property (apb_test_read) 
  begin $display ("Assertion passed with setup and access_phase",$time); end 
    else 
      begin `uvm_error ("Assertion Failure",$sformatf ("Assertion failed for apb_test_read with psel value : %b, pwrite value : %b, pready value : %b, penable value %b, paddr value : %h, pwdata value %h", $sampled(psel),$sampled(pwrite),$sampled(pready),$sampled(penable),$sampled(paddr),$sampled(prdata))); 
     end*/
    
  
   /*  property p2;
       @(posedge pclk)
       $rose(psel) && pwrite |-> !penable ##1  
        $rose (penable) ##0 
       $stable ((paddr) && $stable (pwdata)) until_with pready ##1  !psel && !penable ;// !psel is questionable here 
     endproperty*/
     //  assert property (p2) $display ("Assertion passed",$time);

endinterface: apb_if



    
    
    class apb_base_test extends uvm_test;

  //Register with factory
  `uvm_component_utils(apb_base_test);
  
  apb_env  env;
  apb_config cfg;
  virtual apb_if vif;
  
  function new(string name = "apb_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //Build phase - Construct the cfg and env class using factory
  //Get the virtual interface handle from Test and then set it config db for the env component
  function void build_phase(uvm_phase phase);
    cfg = apb_config::type_id::create("cfg", this);
    env = apb_env::type_id::create("env", this);
    //
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
       `uvm_fatal("APB/DRV/NOVIF", "No virtual interface specified for this test instance")
    end 
    uvm_config_db#(virtual apb_if)::set( this, "env", "vif", vif);
  endfunction

  //Run phase - Create an abp_sequence and start it on the apb_sequencer
  task run_phase( uvm_phase phase );
    apb_base_seq apb_seq;
    apb_seq = apb_base_seq::type_id::create("apb_seq");
    phase.raise_objection( this, "Starting apb_base_seqin main phase" );
    $display("%t Starting sequence apb_seq run_phase",$time);
    apb_seq.start(env.agt.sqr);
    #200ns;
    phase.drop_objection( this , "Finished apb_seq in main phase" );
  endtask: run_phase
  
  
endclass



