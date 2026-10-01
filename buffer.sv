/* Buffer is also doing the same operation like fifo
When data is coming from SPI slave it can able to send bit by bit only at every clk edge,
But APB can be able to receive 32 bits.So we are storing into a buffer after being storing all the 32 bits
bits it will send to the API slave.
It is also doing the same operation like FIFO,it holds the data until all 32 bits received.*/ 






module buffer(
    input        pclk,
    input        rst,
    input  [7:0] slave_data,
    output reg [31:0] p_out
);

reg [31:0] buffer;
  reg [31:0] status_buffer;
reg [1:0] counter;      

  always @(posedge pclk or posedge rst) begin
    if(rst) begin
        buffer  <= 32'd0;
        p_out   <= 32'd0;
        counter <= 2'd0;
    end
    else begin
        buffer <= {buffer[23:0], slave_data};

        if(counter == 2'd3) begin
          p_out   <= {buffer[23:0], slave_data};  //when counter==3 i.e buffer received 4 bytes 
            counter <= 2'd0;
        end
        else begin
            counter <= counter + 1'b1;  //otherwise counter increments upto 3
        end
    end
end

endmodule
