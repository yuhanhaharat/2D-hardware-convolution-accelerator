# 2D convolution hardware accelerator

This is a hardware implementation of a 2D convolution kernal. The parameterized
verilog code can take any given size of weight matrix and input images and generated
output convolved image. The stride is 1 and padding zero techinique is used.

In addition, a simplfied AXI memory interface (mem_if.v) is deployed in order to establish a easy
interface with RISC-V core that I previously built. Computation is performed in compute.v
by using a FSM. PE core is written in pe.v which is the essential part of the computation.

The computation took in place inside of the PE core is shown as below, as can be seen, three
PE core is used and can stream input image in a parallel manner. Each PE core equips with a FIFO. 
A input FIFO and a final output FIFO is used for data  buffering before written back to the memory.

![img.png](img.png)

Also, memory write and read burst modes are implemented to further speed up in hardware. Burst length 
is chosen to be weight matrix size or feature map size. In simple words, once read or write address
is assert, a chuck of data is read out from memory in the following cycle and buffered in FIFO.

Below is a diagram showing my design with all signals and FSM for both memory interface 
and computation unit

![img_2.png](img_2.png)

![img_3.png](img_3.png)



