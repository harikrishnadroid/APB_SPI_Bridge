//APB master verilog code

// Code your design here
module apb_master(
    input         pclk,
    input         prst,
    input         cpu_valid,      
    input         wr_cpu,
    input         pready,
    input  [31:0] prdata,
    input  [31:0] tx_data,
    input  [31:0] cpu_paddr,
    input         pslverr,
    output reg [31:0] paddr,
    output reg        penable,
    output reg        psel,
    output reg [31:0] rx_data,
    output reg        pwrite,
    output reg [31:0] pwdata
);

parameter idle   = 2'b00;
parameter setup  = 2'b01;
parameter access = 2'b10;

reg [1:0] present_state;
reg [1:0] next_state;


always @(posedge pclk or posedge prst)begin
    if(prst)
        present_state <= idle;
    else
        present_state <= next_state;
end


always @(*)begin
  
    next_state = present_state;
    psel    = 1'b0;
    penable = 1'b0;

    case(present_state)

        idle:begin
            if(cpu_valid)
                next_state = setup;
            else
                next_state = idle;
        end

        setup:begin
            psel = 1'b1;
            next_state = access;
        end
      
        access:begin
            psel    = 1'b1;
            penable = 1'b1;

            if(pready)
                next_state = idle;
            else
                next_state = access;
        end

        default:
            next_state = idle;

    endcase

end

always @(posedge pclk or posedge prst)
begin

    if(prst)
    begin
        paddr   <= 32'd0;
        pwdata  <= 32'd0;
        pwrite  <= 1'b0;
        rx_data <= 32'd0;
    end

    else  begin
        case(present_state)
            setup:begin
                paddr  <= cpu_paddr;
                pwdata <= tx_data;
                pwrite <= wr_cpu;
            end
            access:begin
                paddr  <= paddr;
                pwdata <= pwdata;
                pwrite <= pwrite;

              if(psel && penable && !pwrite && pready)
                    rx_data <= prdata;
            end
            default:begin
                paddr  <= paddr;
                pwdata <= pwdata;
                pwrite <= pwrite;
            end
        endcase
    end
end

endmodule
