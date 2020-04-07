module camera #(
    parameter NUM_LANES = 2
) (
    input logic clock_p,
    input logic clock_n,
    input logic [NUM_LANES-1:0] data_p,
    input logic [NUM_LANES-1:0] data_n,
    // See Section 12 for how this should be parsed
    output logic [31:0] raw_data = 32'd0,
    // Corresponding virtual channel for the raw data
    output logic [1:0] virtual_channel = 2'd0,
    // Total number of words in the current packet
    output logic [15:0] word_count = 16'd0,
    // Whether there is output data ready
    output logic raw_data_enable = 1'd0
);

logic [NUM_LANES-1:0] reset = NUM_LANES'(0);
logic [7:0] data [NUM_LANES-1:0];
logic [NUM_LANES-1:0] enable;

genvar i;
generate
    for (i = 0; i < NUM_LANES; i++)
    begin: lane_receivers
        d_phy_receiver d_phy_receiver (
            .clock_p(clock_p),
            .clock_n(clock_n),
            .data_p(data_p[i]),
            .data_n(data_n[i]),
            .reset(reset),
            .data(data[i]),
            .enable(enable[i])
        );
    end
endgenerate

logic [7:0] packet_header [3:0] = 32'd0;
assign virtual_channel = packet_header[0][7:6];
logic [5:0] data_type;
assign data_type = packet_header[0][5:0];
assign word_count = {packet_header[2], packet_header[1]}; // Recall: LSB first
logic [7:0] header_ecc;
assign header_ecc = packet_header[3];

logic [2:0] header_index = 3'd0;
logic [16:0] word_counter = 17'd0;
logic [2:0] data_index = 3'd0;

// Count off multiples of four
assign raw_data_enable == word_counter > 17'd2 && (word_counter - 17'd2) % 4 == 16'd0;

integer j;
always @(posedge clock_p or posedge clock_n)
begin
    // Lane reception
    for (j = 0; j < NUM_LANES; j++)
    begin
        if (enable[j]) // Receive byte
        begin
            if (header_index < 3'd4) // Packet header
            begin
                packet_header[header_index] = data[j];
                header_index = header_index + 1'd1;
            end
            else if (data_type > 8'h0F) // Long packet receive
            begin
                if (header_index == 3'd4)
                begin
                    word_counter = word_count + 17'd1; // Accounts for 2 additional bytes at the end from packet footer
                    header_index = 3'd5;
                end
                else
                    word_counter = word_counter - 17'd1;

                // Raw data
                if (word_counter >= 17'd2)
                begin
                    raw_data[data_index] = data[j];
                    data_index = data_index + 2'd1; // Wrap-around 4 byte
                end
                // Footer
                else
                begin
                end
            end
        end
    end

    // Lane resetting
    for (j = 0; j < NUM_LANES; j++)
    begin
        if (data_type <= 8'h0F && header_index + 3'(j) >= 3'd4 && !reset[j]) // Reset on short packet end
        begin
            reset[j] <= 1'b1;
        end
        // else if (header_index >= 3'd3 && word_counter)
        else if (header_index == 3'd5 && word_counter <= 17'(j) && !reset[j]) // Reset on long packet end
            reset[j] <= 1'b1;
        else // No reset otherwise
            reset[j] <= 1'b0;
    end
    // State reset (next clock)
    if (reset[0]) // Know the entire state is gone for sure if the first lane resets
    begin
        packet_header <= 32'd0;
        header_index <= 4'd0;
        word_counter <= 17'd0;
        data_index <= 4'd0;
    end
end

endmodule
