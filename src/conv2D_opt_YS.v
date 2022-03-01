module conv2D_opt_ys #(
    parameter AWIDTH  = 32,
    parameter DWIDTH  = 32,
    parameter WT_DIM  = 3
) (
    input clk,
    input rst,

    // Control/Status signals
    input start,
    output idle,
    output done,

    // Scalar signals
    input  [31:0]       fm_dim,
    input  [31:0]       wt_offset,
    input  [31:0]       ifm_offset,
    input  [31:0]       ofm_offset,

    // Read Request Address channel
    output [AWIDTH-1:0] req_read_addr,
    output              req_read_addr_valid,
    input               req_read_addr_ready,
    output [31:0]       req_read_len, // burst length

    // Read Response channel
    input [DWIDTH-1:0]  resp_read_data,
    input               resp_read_data_valid,
    output              resp_read_data_ready,

    // Write Request Address channel
    output [AWIDTH-1:0] req_write_addr,
    output              req_write_addr_valid,
    input               req_write_addr_ready,
    output [31:0]       req_write_len, // burst length

    // Write Request Data channel
    output [DWIDTH-1:0] req_write_data,
    output              req_write_data_valid,
    input               req_write_data_ready,

    // Write Response channel
    input                resp_write_status,
    input                resp_write_status_valid,
    output               resp_write_status_ready
);
    
    wire [AWIDTH-1:0]  wt_addr;
    wire [DWIDTH-1:0]  wt_dout;
    wire wt_dout_valid;
    wire wt_dout_ready;
    
    wire [AWIDTH-1:0]  ifm_addr;
    wire [DWIDTH-1:0]  ifm_dout;
    wire ifm_dout_valid;
    wire ifm_dout_ready;

    wire [AWIDTH-1:0] ofm_addr;
    wire [DWIDTH-1:0] ofm_din;
    wire ofm_din_valid;
    wire ofm_din_ready;

    wire compute_start, compute_done, compute_idle;

    // Memory Interface Unit -- to interface with IO-DMem controller
    Conv_mem_if_YS # (
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .WT_DIM(WT_DIM)
    ) mem_if_unit (
        .clk(clk),
        .rst(done | rst),

        // Read Request Address channel
        .req_read_addr_valid(req_read_addr_valid),                  // input
        .req_read_addr_ready(req_read_addr_ready),                  // output
        .req_read_addr(req_read_addr),                              // input
        .req_read_len(req_read_len),                                // input
        .req_read_data(resp_read_data),                            // output
        .req_read_data_valid(resp_read_data_valid),                // output
        .req_read_data_ready(resp_read_data_ready),                // input

        // Write Request Address channel
        .req_write_addr_valid(req_write_addr_valid),       // input
        .req_write_addr_ready(req_write_addr_ready),       // output
        .req_write_addr(req_write_addr),                   // input
        .req_write_len(req_write_len),                     // input
        .req_write_data(req_write_data),                   // input
        .req_write_data_valid(req_write_data_valid),       // input
        .req_write_data_ready(req_write_data_ready),       // output

        // Write Response channel
        .resp_write_status(resp_write_status),             // input
        .resp_write_status_valid(resp_write_status_valid), // input
        .resp_write_status_ready(resp_write_status_ready), // output
        
        .fm_dim(fm_dim),                                   // input
        .wt_offset(wt_offset),                             // input
        .ifm_offset(ifm_offset),                           // input
        .ofm_offset(ofm_offset),                           // input
        
        // DDR addresses of IFM, WT, OFM
        .wt_addr(wt_addr),
        .wt_dout(wt_dout),
        .wt_dout_valid(wt_dout_valid),
        .wt_dout_ready(wt_dout_ready), 
        
        // ifm read (ifm read request from compute unit)
        .ifm_addr(ifm_addr),
        .ifm_dout(ifm_dout),
        .ifm_dout_valid(ifm_dout_valid),
        .ifm_dout_ready(ifm_dout_ready), 
        
        // ofm write (// write request from compute_unit)
        .ofm_addr(ofm_addr),
        .ofm_din(ofm_din),
        .ofm_din_valid(ofm_din_valid), 
        .ofm_din_ready(ofm_din_ready));

    // Compute Unit
    conv2D_opt_compute_YS #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .WT_DIM(WT_DIM)
    ) compute_unit (
        .clk(clk),
        .rst(done | rst),

        // control & status signals
        .compute_start(compute_start),     // input
        .compute_idle(compute_idle),       // output
        .compute_done(compute_done),       // output

        .fm_dim(fm_dim),                    // input
        
        // DDR addresses of IFM, WT, OFM
        .wt_addr(wt_addr),
        .wt_dout(wt_dout),
        .wt_dout_valid(wt_dout_valid),
        .wt_dout_ready(wt_dout_ready), 
        
        // ifm read (ifm read request from compute unit)
        .ifm_addr(ifm_addr),
        .ifm_dout(ifm_dout),
        .ifm_dout_valid(ifm_dout_valid),
        .ifm_dout_ready(ifm_dout_ready), 
        
        // ofm write (// write request from compute_unit)
        .ofm_addr(ofm_addr),
        .ofm_din(ofm_din),
        .ofm_din_valid(ofm_din_valid), 
        .ofm_din_ready(ofm_din_ready));
        
    assign compute_start = start;
    assign done     = compute_done;
    assign idle     = compute_idle;

endmodule