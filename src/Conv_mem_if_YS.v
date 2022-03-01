module Conv_mem_if_YS#(
    parameter AWIDTH = 32,
    parameter DWIDTH = 32,
    parameter WT_DIM = 3
) (
    input clk,
    input rst,
    
    // Read Interface with Memory
    output               req_read_addr_valid,
    input                req_read_addr_ready,
    output [AWIDTH-1:0]  req_read_addr,
    output [31:0]        req_read_len,              // burst length
    input  [DWIDTH-1:0]  req_read_data,
    input                req_read_data_valid,
    output               req_read_data_ready,

    // Write Interface with Memory
    output               req_write_addr_valid,
    input                req_write_addr_ready,
    output [AWIDTH-1:0]  req_write_addr,
    output [31:0]        req_write_len,             // burst length
    output [DWIDTH-1:0]  req_write_data,
    output               req_write_data_valid,
    input                req_write_data_ready,
    
    // Write Response channel
    input                resp_write_status,
    input                resp_write_status_valid,
    output               resp_write_status_ready,
    
    // Scalar input signals
    input  [31:0] fm_dim,
    input  [31:0] wt_offset,
    input  [31:0] ifm_offset,
    input  [31:0] ofm_offset,
    
    // WT read (wt read request from compute unit)
    input  [AWIDTH-1:0] wt_addr,
    output [DWIDTH-1:0] wt_dout,
    output              wt_dout_valid,
    input               wt_dout_ready, 
    
    // ifm read (ifm read request from compute unit)
    input  [AWIDTH-1:0] ifm_addr,
    output [DWIDTH-1:0] ifm_dout,
    output              ifm_dout_valid,
    input               ifm_dout_ready, 
    
    // ofm write (// write request from compute_unit)
    input [AWIDTH-1:0]  ofm_addr,
    input [DWIDTH-1:0]  ofm_din,
    input         ofm_din_valid, 
    output        ofm_din_ready
);
    
    wire req_read_addr_fire = req_read_addr_valid && req_read_addr_ready;
    wire req_read_data_fire = req_read_data_valid && req_read_data_ready;
    wire req_write_addr_fire = req_write_addr_valid && req_write_addr_ready;
    wire req_write_data_fire = req_write_data_valid && req_write_data_ready;
    
    wire fetch_wt  = wt_dout_ready;
    wire fetch_ifm = ifm_dout_ready;
    wire write_ofm = ofm_din_valid;
    
    localparam STATE_IDLE               = 0;
    localparam STATE_READ_WT_ADDR_REQ   = 1;
    localparam STATE_READ_WT_DATA       = 2;
    localparam STATE_READ_IFM_ADDR_REQ  = 3;
    localparam STATE_READ_IFM_DATA      = 4;
    localparam STATE_WRITE_ADDR_REQ     = 5;
    localparam STATE_WRITE_DATA         = 6;
    localparam STATE_DONE               = 7;
    
    wire [2:0] state_value;
    reg  [2:0] state_next;
    REGISTER_R #(.N(3), .INIT(STATE_IDLE)) state_reg (
        .clk(clk),
        .rst(rst),
        .d(state_next),
        .q(state_value));
        
    wire idle               = state_value == STATE_IDLE;
    wire read_wt_addr_req   = state_value == STATE_READ_WT_ADDR_REQ;
    wire read_wt_data       = state_value == STATE_READ_WT_DATA;
    wire read_ifm_addr_req  = state_value == STATE_READ_IFM_ADDR_REQ;
    wire read_ifm_data      = state_value == STATE_READ_IFM_DATA;
    wire write_addr_req     = state_value == STATE_WRITE_ADDR_REQ;
    wire write_data         = state_value == STATE_WRITE_DATA;
    wire done               = state_value == STATE_DONE;
    
    always @(*) begin
        state_next = state_value;
        case (state_value)
        STATE_IDLE: begin
          if (fetch_wt)
            state_next = STATE_READ_WT_ADDR_REQ;
          else if(fetch_ifm)
            state_next = STATE_READ_IFM_ADDR_REQ;  
          else if (write_ofm)
            state_next = STATE_WRITE_ADDR_REQ;
        end
    
        STATE_READ_WT_ADDR_REQ: begin
          if (req_read_addr_fire)
            state_next = STATE_READ_WT_DATA;
        end
    
        STATE_READ_WT_DATA: begin
          if (~req_read_data_fire && ~fetch_wt)
            state_next = STATE_DONE;
        end
        
        STATE_READ_IFM_ADDR_REQ: begin
          if (req_read_addr_fire)
            state_next = STATE_READ_IFM_DATA;
        end
    
        STATE_READ_IFM_DATA: begin
          if (~req_read_data_fire && ~fetch_ifm)
            state_next = STATE_DONE;
        end
        
        STATE_WRITE_ADDR_REQ: begin
          if (req_write_addr_fire)
            state_next = STATE_WRITE_DATA;
        end
    
        STATE_WRITE_DATA: begin
          if (~req_write_data_fire && ~write_ofm)
            state_next = STATE_DONE;
        end
    
        STATE_DONE: begin
          state_next = STATE_IDLE;
        end
        endcase
    end

    // Read Interface with Memory related signal    
    assign req_read_addr_valid   = read_ifm_addr_req | read_wt_addr_req;
    assign req_read_addr         = fetch_wt ?  (wt_offset + wt_addr) : (ifm_offset + ifm_addr);
    assign req_read_len          = fetch_wt ?  WT_DIM * WT_DIM : 
                                   fetch_ifm ? fm_dim * fm_dim : 0;
    assign req_read_data_ready   = read_ifm_data | read_wt_data;
    
    // Write Interface with Memory related signal    
    assign req_write_addr_valid  = write_addr_req;
    assign req_write_addr        = ofm_offset;
    assign req_write_len         = fm_dim * fm_dim;
    assign req_write_data        = ofm_din;
    assign req_write_data_valid  = write_data;
    
    // signals related to compute unit  
    assign wt_dout               = req_read_data;
    assign ifm_dout              = req_read_data;
    
    assign wt_dout_valid         = read_wt_data  && req_read_data_valid;
    assign ifm_dout_valid        = read_ifm_data  && req_read_data_valid;
    
    assign ofm_din_ready         = write_data && req_write_data_fire;
    assign resp_write_status_ready = 1'b1;                              // keep it simple
    
endmodule
