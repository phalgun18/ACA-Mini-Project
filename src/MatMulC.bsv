
package MatMul;

import Vector   :: *;
import FIFOF    :: *;
import MM_Types :: *;

function C_Mat f_step (A_Mat a, B_Mat b, C_Mat c, UInt #(8) l);
   C_Mat o = c;
   for (Integer i = 0; i < m_dim; i = i + 1)
      for (Integer j = 0; j < n_dim; j = j + 1) begin
         Int #(16) p = signedMul (a[i][l], b[l][j]);
         o[i][j] = c[i][j] + signExtend (p);
      end
   return o;
endfunction

(* synthesize *)
module mkMatMul (MatMul_IFC);

   Reg #(A_Mat) rg_a  <- mkReg (replicate (replicate (0)));
   Reg #(B_Mat) rg_b  <- mkReg (replicate (replicate (0)));
   Reg #(A_Mat) rg_wa <- mkReg (replicate (replicate (0)));
   Reg #(B_Mat) rg_wb <- mkReg (replicate (replicate (0)));
   Reg #(C_Mat) rg_c  <- mkReg (replicate (replicate (0)));

   Reg #(Bool)      rg_busy <- mkReg (False);   
   Reg #(UInt #(8)) rg_l    <- mkReg (0);       

   FIFOF #(MM_Req) f_req <- mkFIFOF;
   FIFOF #(MM_Rsp) f_rsp <- mkFIFOF;

   rule rl_step (rg_busy);
      rg_c <= f_step (rg_wa, rg_wb, rg_c, rg_l);
      if (rg_l == fromInteger (k_dim - 1)) begin
         rg_busy <= False;
         rg_l    <= 0;
      end
      else
         rg_l <= rg_l + 1;
   endrule

   rule rl_load_a (f_req.first matches tagged LoadA .w);
      f_req.deq;
      let a = rg_a;
      a[w.row] = reverse (unpack (w.word));
      rg_a <= a;
      f_rsp.enq (mm_rsp_none);
   endrule

   rule rl_load_b (f_req.first matches tagged LoadB .w);
      f_req.deq;
      let b = rg_b;
      b[w.row] = reverse (unpack (w.word));
      rg_b <= b;
      f_rsp.enq (mm_rsp_none);
   endrule

   rule rl_mul (!rg_busy &&& f_req.first matches tagged Mul);
      f_req.deq;
      rg_wa <= rg_a;
      rg_wb <= rg_b;
      rg_c  <= f_step (rg_a, rg_b, rg_c, 0);
      if (k_dim > 1) begin
         rg_busy <= True;
         rg_l    <= 1;
      end
      f_rsp.enq (mm_rsp_none);
   endrule

   rule rl_read_c (!rg_busy &&& f_req.first matches tagged ReadC .x);
      f_req.deq;
      let c = rg_c;
      Acc v = c [x.row][x.chunk];
      c [x.row][x.chunk] = 0;
      rg_c <= c;
      f_rsp.enq (mm_rsp_value (pack (v)));
   endrule

   method Action req (MM_Req r) = f_req.enq (r);

   method ActionValue #(MM_Rsp) rsp;
      f_rsp.deq;
      return f_rsp.first;
   endmethod
endmodule

endpackage: MatMul
