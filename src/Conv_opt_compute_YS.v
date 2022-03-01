module conv2D_opt_compute_YS #(
    parameter AWIDTH = 32,
    parameter DWIDTH = 32,
    parameter WT_DIM = 3
) (
    input clk,
    input rst,
    
    // WT read
    output [AWIDTH-1:0]     wt_addr,
    input  [DWIDTH-1:0]     wt_dout,
    input                   wt_dout_valid,
    output                  wt_dout_ready,
    
    // IFM read
    output [AWIDTH-1:0]     ifm_addr,
    input  [DWIDTH-1:0]     ifm_dout,
    input                   ifm_dout_valid,
    output                  ifm_dout_ready,
    
    // OFM write
    output [AWIDTH-1:0] ofm_addr,
    output [DWIDTH-1:0] ofm_din,
    output        ofm_din_valid,
    input         ofm_din_ready,
    output        ofm_we,
    
    // control & status signals
    input  compute_start,
    output compute_idle,
    output compute_done,
    
    // Feature map dimension
    input [31:0] fm_dim
);
    
    localparam halo_cnt  = (WT_DIM - 1);         //2
    localparam half_halo_cnt = halo_cnt >> 1;    //1
    localparam WT_SIZE = WT_DIM * WT_DIM;        //3x3=9
   
    wire [31:0] x_cnt_edge = (fm_dim + halo_cnt - 1);           //ifm col size   
    wire [31:0] y_cnt_edge = (fm_dim + halo_cnt - 1);           //ifm row size
    wire halo;                                                  //padded_zero
    
    wire ifm_dout_fire  = ifm_dout_valid  & ifm_dout_ready;
    wire wt_dout_fire   = wt_dout_valid   & wt_dout_ready;
    wire ofm_din_fire   = ofm_din_valid   & ofm_din_ready;
    
    localparam STATE_IDLE         = 0;
    localparam STATE_FETCH_WT     = 1;
    localparam STATE_COMPUTE      = 2;
    localparam STATE_WRITE_OFM    = 3;
    localparam STATE_DONE         = 4;
    localparam STATE_FINISH       = 5;
    
    wire [2:0] state_value;
    reg  [2:0] state_next;
    
    wire idle          = state_value == STATE_IDLE;
    wire fetch_wt      = state_value == STATE_FETCH_WT;
    wire compute       = state_value == STATE_COMPUTE;
    wire write_ofm     = state_value == STATE_WRITE_OFM;
    wire done          = state_value == STATE_DONE;
    wire finish          = state_value == STATE_FINISH;

    wire read_wt_success   = fetch_wt  & wt_dout_fire;
    wire read_ifm_success  = compute   & ifm_dout_fire;
    wire write_ofm_success = write_ofm & ofm_din_fire;
      
    REGISTER_R #(.N(3), .INIT(STATE_IDLE)) state_reg (
        .clk(clk),
        .rst(rst),
        .d(state_next),
        .q(state_value));
    
    // m index register: 0 --> WT_DIM - 1
    wire [31:0] m_cnt_d, m_cnt_q;
    wire m_cnt_ce, m_cnt_rst;
    REGISTER_R_CE #(.N(32), .INIT(0)) m_cnt_reg (
        .q(m_cnt_q),
        .d(m_cnt_d),
        .ce(m_cnt_ce),
        .rst(m_cnt_rst),
        .clk(clk));
    
    // n index register: 0 --> WT_DIM - 1
    wire [31:0] n_cnt_d, n_cnt_q;
    wire n_cnt_ce, n_cnt_rst;
    REGISTER_R_CE #(.N(32), .INIT(0)) n_cnt_reg (
        .q(n_cnt_q),
        .d(n_cnt_d),
        .ce(n_cnt_ce),
        .rst(n_cnt_rst),
        .clk(clk));
    
    // x index register for current IFM
    wire [31:0] x_cnt_d, x_cnt_q;
    wire x_cnt_ce, x_cnt_rst;
    REGISTER_R_CE #(.N(32), .INIT(0)) x_cnt_reg (
        .q(x_cnt_q),
        .d(x_cnt_d),
        .ce(x_cnt_ce),
        .rst(x_cnt_rst),
        .clk(clk));
    
    // y index register for current IFM
    wire [31:0] y_cnt_d, y_cnt_q;
    wire y_cnt_ce, y_cnt_rst;
    REGISTER_R_CE #(.N(32), .INIT(0)) y_cnt_reg (
        .q(y_cnt_q),
        .d(y_cnt_d),
        .ce(y_cnt_ce),
        .rst(y_cnt_rst),
        .clk(clk));
    
    // count output write progress
    wire [31:0] write_counter_d;
            wire [31:0] write_counter_q;
            wire write_counter_ce, write_counter_rst;
            REGISTER_R_CE #(.N(32)) write_counter (
                .q(write_counter_q),
                .d(write_counter_d),
                .ce(write_counter_ce),
                .rst(write_counter_rst),
                .clk(clk));

    // keep the state of the done signal
    // It needs to stay HIGH after the compute is done
    // and restart to 0 once the compute starts again
    wire compute_done_next, compute_done_value;
    wire compute_done_ce, compute_done_rst;
    REGISTER_R_CE #(.N(1), .INIT(0)) compute_done_reg (
      .clk(clk),
      .rst(compute_done_rst),
      .d(compute_done_next),
      .q(compute_done_value),
      .ce(compute_done_ce));
      
    // read ifm data from io_mem
    wire [DWIDTH-1:0] fifo_deq_read_data;
    wire fifo_deq_read_data_valid, fifo_deq_read_data_ready;
    wire fifo_rdata_fire;
    wire [DWIDTH-1:0] wt_ifm_dout;
    wire wt_ifm_dout_valid,wt_ifm_dout_ready;
    wire wt_ifm_dout_fire;
    
    fifo #(.WIDTH(DWIDTH), .LOGDEPTH(13)) data_in_fifo (
          .clk(clk),
          .rst(rst),
  
          .enq_valid(wt_ifm_dout_valid),
          .enq_data(wt_ifm_dout),
          .enq_ready(wt_ifm_dout_ready),
  
          .deq_valid(fifo_deq_read_data_valid),
          .deq_data(fifo_deq_read_data),
          .deq_ready(fifo_deq_read_data_ready)); 
    
    // write ofm data to io_mem
    wire [DWIDTH-1:0] fifo_enq_write_data;
    wire fifo_enq_write_data_valid, fifo_enq_write_data_ready;
    wire ofm_din_valid_temp;
    
    fifo #(.WIDTH(DWIDTH), .LOGDEPTH(13)) data_out_fifo(
          .clk(clk),
          .rst(rst),
  
          .enq_valid(fifo_enq_write_data_valid),
          .enq_data(fifo_enq_write_data),
          .enq_ready(fifo_enq_write_data_ready),
  
          .deq_valid(ofm_din_valid_temp),
          .deq_data(ofm_din),
          .deq_ready(ofm_din_ready));
    
    // Generate instances of PE
    wire [DWIDTH-1:0] pe_weight_data, pe_fm_data;
    wire pe_fm_data_valid;
    
    wire [DWIDTH-1:0] pe_data_outputs[WT_DIM-1:0];
    wire pe_data_valids[WT_DIM-1:0];
    wire pe_rst;
    wire pe_weight_data_valid;
    genvar i;
    generate
          for (i = 0; i < WT_DIM; i = i + 1) begin:PE
              conv2D_pe #(.AWIDTH(AWIDTH),
                          .DWIDTH(DWIDTH),
                          .WT_DIM(WT_DIM)) pe (
                          .clk(clk),
                          .rst(rst),
                          .index_i(i),
                          .fm_dim(fm_dim),
                          .pe_weight_data_i(pe_weight_data),
                          .pe_weight_data_valid(pe_weight_data_valid),
                          .pe_fm_data_i(pe_fm_data),
                          .pe_fm_data_valid(pe_fm_data_valid),
                          .pe_data_o(pe_data_outputs[i]),
                          .pe_data_valid(pe_data_valids[i]));
          end
    endgenerate
    
    // Generate fifo for each PE
    wire pe_fifo_enq_ready[WT_DIM-1:0] ;
    wire pe_fifo_deq_ready[WT_DIM-1:0];
    wire pe_fifo_deq_valids[WT_DIM-1:0];
    wire [DWIDTH-1:0] pe_fifo_deq_datas[WT_DIM-1:0];

    generate
        for (i = 0; i < WT_DIM; i = i + 1) begin:FIFO
          fifo #(.WIDTH(32), .LOGDEPTH(9)) fifo_in (
              .clk(clk),
              .rst(rst),

              .enq_valid(pe_data_valids[i]),
              .enq_data(pe_data_outputs[i]),
              .enq_ready(pe_fifo_enq_ready[i]),

              .deq_valid(pe_fifo_deq_valids[i]),
              .deq_data(pe_fifo_deq_datas[i]),
              .deq_ready(pe_fifo_deq_ready[i]));
        end
    endgenerate
    
    always @(*) begin
        state_next = state_value;
    
        case (state_value)
          STATE_IDLE: begin
            if (compute_start) begin
              state_next = STATE_FETCH_WT;
            end
          end
          
          // fetch weight elements
          STATE_FETCH_WT: begin
            if (n_cnt_q == WT_DIM - 1 & m_cnt_q == WT_DIM - 1 & fifo_rdata_fire)
              state_next = STATE_COMPUTE;
          end
            
          // fetch IFM elements and compute
          STATE_COMPUTE: begin
            if (x_cnt_q == x_cnt_edge & y_cnt_q == y_cnt_edge & (fifo_rdata_fire | halo))
              state_next = STATE_WRITE_OFM;
          end
       
          // write back to memory
          STATE_WRITE_OFM: begin
              if (write_counter_rst) begin
                state_next = STATE_DONE;
              end
          end
    
          STATE_DONE: begin
              if(~ofm_din_valid_temp) begin         // drain the output FIFO until empty
                    state_next = STATE_FINISH;
              end
          end
          
          STATE_FINISH: begin
                state_next = STATE_IDLE;
          end
        endcase
      end
    
      assign compute_idle = idle;
      assign compute_done = compute_done_value;
      assign compute_done_next = 1'b1;
      assign compute_done_ce   = finish;
      assign compute_done_rst  = (idle & compute_start) | rst;  
    
      // wt address, ifm address and ofm address
      assign wt_addr  = 0;
      assign ifm_addr = 0;
      assign ofm_addr = 0;

      // memory data (weight) to input FIFO 
      assign wt_ifm_dout_valid  = fetch_wt ? wt_dout_valid  : 
                                  compute  ? ifm_dout_valid : 0;
      assign wt_ifm_dout        = fetch_wt ? wt_dout        : 
                                  compute  ? ifm_dout       : 0;
      assign wt_dout_ready      = wt_ifm_dout_ready & fetch_wt;
      assign ifm_dout_ready     = wt_ifm_dout_ready & compute;
      
      assign fifo_rdata_fire = fifo_deq_read_data_valid && fifo_deq_read_data_ready;      
      assign fifo_deq_read_data_ready = fetch_wt | (compute & ~halo);
      
      // load weight to PE
      assign pe_weight_data_valid     = fetch_wt & fifo_rdata_fire;
      assign pe_weight_data           = fifo_deq_read_data;
      
      assign m_cnt_d      = m_cnt_q + 1;
      assign m_cnt_ce     = fetch_wt & fifo_rdata_fire & (n_cnt_q == WT_DIM - 1);
      assign m_cnt_rst    = ((m_cnt_q == WT_DIM - 1) & (n_cnt_q == WT_DIM - 1) & fifo_rdata_fire) | rst;
  
      assign n_cnt_d      = n_cnt_q + 1;
      assign n_cnt_ce     = fetch_wt & fifo_rdata_fire;
      assign n_cnt_rst    = (n_cnt_q == WT_DIM - 1 & fifo_rdata_fire) | rst;
       
      // load ifm to PE 
      assign pe_fm_data_valid   = (compute | write_ofm) & fifo_rdata_fire;
      assign pe_fm_data         = fifo_deq_read_data;
      assign halo         = (x_cnt_q < half_halo_cnt) | (y_cnt_q < half_halo_cnt)
                                                      | (x_cnt_q > (x_cnt_edge - half_halo_cnt))
                                                      | (y_cnt_q > (y_cnt_edge - half_halo_cnt));
      
      assign x_cnt_d      = x_cnt_q + 1;
      assign x_cnt_ce     = compute & (fifo_rdata_fire | halo);
      assign x_cnt_rst    = (compute & x_cnt_q == x_cnt_edge & (fifo_rdata_fire | halo)) | rst;
  
      assign y_cnt_d      = y_cnt_q + 1;
      assign y_cnt_ce     = compute & (x_cnt_q == x_cnt_edge) & (fifo_rdata_fire | halo);
      assign y_cnt_rst    = (compute & x_cnt_q == x_cnt_edge & y_cnt_q == y_cnt_edge & (fifo_rdata_fire | halo)) | rst;     

      // output from PE to output FIFO 
      reg pe_data_valid;                //overall from three output PE FIFO
      reg [DWIDTH-1:0] pe_data_out;     //overall from three output PE FIFO
      wire pe_data_fire;                //overall from three output PE FIFO
      
      integer j;
      always @(*) begin
          pe_data_valid = 1'b1;
          for (j = 0; j < WT_DIM; j = j + 1) begin
              pe_data_valid = pe_data_valid & pe_fifo_deq_valids[j];
          end
      end
      
      generate
          for (i = 0; i < WT_DIM; i = i + 1) begin : pe
              assign pe_fifo_deq_ready[i] = (compute | write_ofm) & pe_data_valid & fifo_enq_write_data_ready;
          end
      endgenerate
      
      always @(*) begin
          pe_data_out = 32'b0;
          for (j = 0; j < WT_DIM; j = j + 1) begin
              pe_data_out = pe_data_out + pe_fifo_deq_datas[j];
          end
      end
      
      // signal to output FIFO
      assign pe_data_fire                 = pe_data_valid & fifo_enq_write_data_ready & (compute | write_ofm);
      assign fifo_enq_write_data          = pe_data_out;
      assign fifo_enq_write_data_valid    = pe_data_valid;
      
      // count number of data that already writtern into output FIFO
      assign write_counter_d      = write_counter_q + 1;
      assign write_counter_ce     = pe_data_fire;
      assign write_counter_rst    = (write_counter_q == fm_dim * fm_dim) | rst;
      
      // When the computation is done, we start write back to the memory
      assign ofm_din_valid        = done;
      
endmodule
