//APB slave verilog code

module apb_slave(
    input              pclk,
    input              prst,
    input              psel,
    input              penable,
    input      [31:0]  paddr,
    input              pwrite,
    input              fifo_full,
    input              busy,
    input      [31:0]  pwdata,
    input      [31:0]  p_out,
    output reg [42:0]  d_in,
    output reg         pready,
    output reg         pslverr,
    output reg [31:0]  prdata,
    output             fifo_wr
);

reg [31:0] control_reg;
reg [31:0] status_reg;
reg [31:0] tx_reg;
reg [31:0] rx_reg;



  assign fifo_wr = psel && penable && pwrite && (paddr == 32'h4) && !fifo_full;


always @(posedge pclk or posedge prst)
begin
  if(prst) begin
        control_reg <= 32'd0;
        tx_reg      <= 32'd0;
        d_in        <= 43'd0;
    end

    else begin
        if(psel && !penable && pwrite)
        begin
            case(paddr)

                32'h0:
                    control_reg <= pwdata;

                32'h4:
                    tx_reg <= pwdata;

            endcase
        end

      if(fifo_wr && paddr==32'h4) begin
          d_in <= {pwdata,control_reg[10:0]};
        end

    end
end



  always @(posedge pclk or posedge prst) begin
    if(prst)
        status_reg <= 32'd0;

    else begin
        status_reg[0] <= fifo_full;
        status_reg[1] <= pready;
      status_reg[2] <= busy;
      status_reg[31:3] <= 30'd0;
    end
end



always @(posedge pclk or posedge prst)
begin
    if(prst)
        rx_reg <= 32'd0;

    else
        rx_reg <= p_out;
end


  always @(posedge pclk or posedge prst)begin
  if(prst) begin
        prdata <= 32'd0;
    end
    else if(psel && penable && !pwrite) begin
        case(paddr)

            32'h8:
                prdata <= status_reg;

            32'hC:
                prdata <= rx_reg;

            default:
                prdata <= 32'd0;

        endcase
    end
end

always @(posedge pclk or posedge prst)begin
    if(prst)
        pready <= 1'b0;

    else if(psel && penable)begin
        if(pwrite)
            pready <= !fifo_full;
        else
            pready <= 1'b1;
    end

    else
        pready <= 1'b0;
end



always @(posedge pclk or posedge prst)begin
    if(prst)
        pslverr <= 1'b0;

  else if(psel && penable) begin

        case(paddr)

            32'h0,
            32'h4,
            32'h8,
            32'hC:
                pslverr <= 1'b0;

            default:
                pslverr <= 1'b1;

        endcase

    end

    else
        pslverr <= 1'b0;
end

endmodule
