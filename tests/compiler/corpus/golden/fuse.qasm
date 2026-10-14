OPENQASM 3.0;
include "stdgates.inc";
qubit[2] q;
rz(0.69999999999999996) q[0];
rx(-1) q[1];
cp(1.5707963267948966) q[0], q[1];
