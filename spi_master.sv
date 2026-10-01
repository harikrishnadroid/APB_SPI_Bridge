//verilog code for SPI master


module spi_master(
    input pclk,
    input rst,
    input miso,
    input fifo_empty,
    input [42:0] d_out,
    output reg [7:0] slave_data,
    output reg read_en,
    output reg start,
    output busy,
    output reg ss,
    output reg mosi,
    output reg sclk
);

parameter idle     = 3'b000;
parameter copy     = 3'b001;
parameter load     = 3'b010;
parameter transfer = 3'b011;
parameter done     = 3'b100;

reg [42:0] dout_reg;
reg [2:0] present_state,next_state;
reg [7:0] master_tx_shift_reg;
reg [7:0] master_rx_shift_reg;
reg [3:0] count;
reg [1:0] byte_count;
reg [7:0] div;
reg cpol;
reg cpha;
reg en;
reg [7:0] clk_count;
reg sclk_d;

wire posedge_sclk;
wire negedge_sclk;
wire sample_en;
wire shift_en;

assign busy = (present_state != idle);


always @(posedge pclk or posedge rst) begin
    if(rst)
        present_state <= idle;
    else
        present_state <= next_state;
end


always @(*) begin

    next_state = present_state;
    read_en = 0;
    start   = 0;
    ss      = 1;

    case(present_state)

        idle:
        begin
            if(!fifo_empty)
            begin
                read_en = 1;
                byte_count <= 0;
                next_state = copy;
            end
        end

        copy:
        begin
            next_state = load;
        end

        load:
        begin
            start = 1;
            next_state = transfer;
        end

        transfer:
        begin
            ss = 0;

          if(count == 9)
            begin
              if(byte_count >= 3)begin
                byte_count=0;
                
                    next_state = done;
              end
                else begin
                    byte_count = byte_count + 1;
                    next_state = load;
                end
            end
        end

        done:begin
          
            ss = 1;
          
            next_state = idle;
        end
    endcase

end


always @(posedge pclk or posedge rst) begin

    if(rst)
        dout_reg <= 0;
  else if(present_state==copy)
        dout_reg <= d_out;

end


always @(posedge pclk or posedge rst) begin

    if(rst)
    begin
        en   <= 0;
        cpol <= 0;
        cpha <= 0;
        div  <= 1;
    end

  else if(present_state==copy || present_state==transfer)
    begin
        en   <= dout_reg[0];
        cpol <= dout_reg[1];
        cpha <= dout_reg[2];
        div  <= dout_reg[10:3];
    end

end


always @(posedge pclk or posedge rst) begin

    if(rst)
    begin
        master_tx_shift_reg <= 0;
        byte_count <= 0;
        count <= 0;
        mosi <= 0;
    end

    else begin

        case(present_state)

            load:begin
               case(byte_count)
                    2'd0: master_tx_shift_reg <= dout_reg[42:35];
                    2'd1: master_tx_shift_reg <= dout_reg[34:27];
                    2'd2: master_tx_shift_reg <= dout_reg[26:19];
                    2'd3: master_tx_shift_reg <= dout_reg[18:11];
                endcase
                mosi <= master_tx_shift_reg[7];
               count <= 0;
            end

            transfer:
            begin
                if(sample_en)
                begin
                    master_rx_shift_reg <= {master_rx_shift_reg[6:0],miso};
                    count <= count + 1;
                end

                if(shift_en)
                begin
                    mosi <= master_tx_shift_reg[6];
                    master_tx_shift_reg <= {master_tx_shift_reg[6:0],1'b0};
                end
            end

            done:
            begin
                slave_data <= master_rx_shift_reg;
                byte_count <= 0;
            end
        endcase
    end
end


// always @(posedge pclk or posedge rst) begin

//     if(rst)
//         byte_count <= 0;

//     else if(present_state==transfer && count==8)
//         byte_count <= byte_count + 1;
// end

always @(posedge pclk or posedge rst) begin

    if(rst)
    begin
        clk_count <= 0;
        sclk <= 0;
    end

  else if(present_state==transfer) begin

        if(clk_count==div) begin
            clk_count <= 0;
            sclk <= ~sclk;
        end
        else
            clk_count <= clk_count + 1;
    end

    else  begin
        clk_count <= 0;
        sclk <= cpol;
    end
end


always @(posedge pclk or posedge rst) begin

    if(rst)
        sclk_d <= 0;
    else
        sclk_d <= sclk;

end

assign posedge_sclk =  sclk & ~sclk_d;
assign negedge_sclk = ~sclk &  sclk_d;

assign sample_en = ((cpol==cpha) && posedge_sclk) || ((cpol!=cpha) && negedge_sclk);

assign shift_en = ((cpol==cpha) && negedge_sclk) || ((cpol!=cpha) && posedge_sclk);

endmodule
