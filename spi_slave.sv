//verilog code for spi slave

module spi_slave #(parameter cpol = 0,
                   parameter cpha = 0)
(
    input        sclk,
    input        rst,
    input        ss,
    input        mosi,
    input  [7:0] slave_tx_data,
    output [7:0] slave_rx_data,
    output       miso
);

reg [7:0] slave_tx1_shift_reg;
reg [7:0] slave_tx2_shift_reg;
reg [7:0] slave_rx1_shift_reg;
reg [7:0] slave_rx2_shift_reg;
reg [2:0] count1;
reg [2:0] count2;
reg [2:0] count3;
reg miso1;
reg miso2;

assign miso = (cpol == cpha) ? miso2 : miso1;
assign slave_rx_data = (cpol == cpha) ? slave_rx1_shift_reg :
                                          slave_rx2_shift_reg;


always @(posedge sclk or posedge rst)
begin
  if(rst) begin
         slave_rx1_shift_reg <= 8'd0;
        slave_tx1_shift_reg <= 8'd0;
        count1 <= 0;
    end
    else if(ss)begin
        slave_tx1_shift_reg <= slave_tx_data;
        count1 <= 0;
    end
  else if(cpol == cpha) begin
        slave_rx1_shift_reg <= {slave_rx1_shift_reg[6:0], mosi};
        count1 <= count1 + 1;
    end
    else begin
        miso1 <= slave_tx1_shift_reg[7];
        slave_tx1_shift_reg <= {slave_tx1_shift_reg[6:0],1'b0};
    end
end



always @(negedge sclk or posedge rst)begin
    if(rst) begin
        slave_rx2_shift_reg <= 8'd0;
        slave_tx2_shift_reg <= 8'd0;
        count2 <= 0;
        count3 <= 0;   
    end
   else if(ss) begin
        //slave_tx2_shift_reg <= slave_tx_data;
        slave_tx2_shift_reg <= 8'ha5;
        count3<=0;
        count2 <= 0;
    end
    else if(cpol == cpha) begin
        miso2 <= slave_tx2_shift_reg[7];
      slave_tx2_shift_reg <= {slave_tx2_shift_reg[6:0],slave_tx2_shift_reg[7]};
      count3<=count3+1;
    end
    else begin
        slave_rx2_shift_reg <= {slave_rx2_shift_reg[6:0], mosi};
        count2 <= count2 + 1;
    end
end

endmodule
