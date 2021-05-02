// Code your design here
module apb_slave   # (
    
  addrWidth = 8,
  dataWidth = 32)


  (input                        pclk,
  input                        rst_n,
  input        [addrWidth-1:0] paddr,
  input                        pwrite,
  input                        psel,
  input                        penable,
  input        [dataWidth-1:0] pwdata,
   input [3:0]                 pstrb,
   output logic [dataWidth-1:0] prdata,
   output logic pready
   );
  
 // parameter addrWidth = 8;
 // parameter dataWidth = 32;
   logic [dataWidth-1:0] mem [256];

  logic [2:0] apb_st;
  const logic [2:0] SETUP = 0;
  const logic [2:0] W_ENABLE = 1;
  const logic [2:0] R_ENABLE = 2;
  const logic [2:0] W_EXTEND = 3;
  const logic [2:0] R_EXTEND = 3;
  

// SETUP -> ENABLE
    always @(negedge rst_n or posedge pclk) begin
      if (rst_n == 0) begin
       apb_st <= 0;
       pready <=0; 
  //  apb_if.prdata <= 0;
  end

  else begin
    case (apb_st)
      SETUP : begin
        // clear the prdata
      prdata <= 0;
     // pready <= 0;  
     //   $display("RD from mem data = %h, addr = %h",$sampled(prdata),paddr,$time);

        // Move to ENABLE when the psel is asserted
        if (psel && !penable) begin
          if (pwrite) begin
            apb_st <= W_ENABLE;
           // repeat (1) @(posedge pclk); 
            pready <=1;
          end

          else begin
            prdata <= mem[paddr];
            apb_st <= R_ENABLE;
         //   repeat (1) @(posedge pclk);
            pready <=1;
            
          end
        end
      end

      W_ENABLE : begin
        // write pwdata to memory
       
          mem[paddr] <= pwdata;
      //    $display("WR to mem data = %h, addr = %h",pwdata,paddr);
          pready <=0;
        
        // return to SETUP
        apb_st <= SETUP;
      end

      R_ENABLE : begin
        // read prdata from memory
   //     if (psel && !pwrite)
          begin
        
         // prdata <= mem[paddr];
           
          pready <=0;
         
        end

        // return to SETUP
        apb_st <= SETUP;
      end
    endcase
  end
end 


endmodule
