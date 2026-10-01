/*Here i have used fifo for temporarily storing the data which is coming from the APB master
Usually APB is very faster than SPI protocol.APB can send 32 bits in a single clk edge buut SPI can send or sample 1 bit at a time.
So SPI can take some time to transfer all the 32 bits.Within that time APB can send another 32 bits.
If it sends it will overwritten by the new data,so previously sent data will be lost so,to avoid that one i have stored in a fifo.
It will send byte by byte to the SPI master.
I have both control_reg data and PWdata into a single addr of fifo.*/


module fifo(
    input              pclk,
    input              prst,
    input              w_en,
    input              r_en,
    input      [42:0]  d_in,
    output reg [42:0]  d_out,
    output             empty,
    output             full
);

reg [42:0] mem [31:0];
reg [4:0] write_pt;
reg [4:0] read_pt;


always @(posedge pclk or posedge prst)
begin
    if(prst)
    begin
        write_pt <= 5'd0;
        read_pt  <= 5'd0;
        d_out    <= 43'd0;
    end
    else begin      
        if(w_en && !full) begin
            mem[write_pt[3:0]] <= d_in;
            write_pt <= write_pt + 1'b1;
        end       
      if(r_en && !empty) begin
            d_out <= mem[read_pt[3:0]];
            read_pt <= read_pt + 1'b1;
        end
    end
end


assign empty = (write_pt == read_pt);
assign full =(write_pt[4] != read_pt[4]) && (write_pt[3:0] == read_pt[3:0]);

endmodule
