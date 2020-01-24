#!/bin/sh
#
# Copyright (C) 2020 Chris McClelland
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software
# and associated documentation files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright  notice and this permission notice  shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
# BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

# Settings for coloured text
NORM=$(tput sgr0)
BOLD=$(tput bold; tput setaf 1)

# Need at least one argument
if [ $# -lt 1 ]; then
    echo "Synopsis: $0 <component>"
    exit 1
fi

if [ -z "${PROJ_HOME}" ]; then
    echo "You need to set PROJ_HOME"
    exit 1
fi
if [ ! -e "${PROJ_HOME}/ip" ]; then
    echo "IP directory does not exist: ${PROJ_HOME}/ip"
    exit 1
fi

OLDIFS=${IFS}
IFS=':'
set -- $1
IFS=${OLDIFS}
if [ "$#" -ne "2" ]; then
    echo "Component names need to look like \"library:proj\""
    exit 1
fi
LIBRARY=$1
COMPONENT_DIR=$2
COMPONENT_NAME=$(echo $COMPONENT_DIR | tr - _)

mkdir -p ${PROJ_HOME}/ip/${LIBRARY}
cd ${PROJ_HOME}/ip/${LIBRARY}

if [ -e "${COMPONENT_DIR}" ]; then
    echo "This component already exists!"
    exit 1
fi

mkdir ${COMPONENT_DIR}
cd ${COMPONENT_DIR}

echo "Creating ${BOLD}Makefile${NORM}..."
cat > Makefile <<EOF
WORK := ${LIBRARY}
SUBDIRS := tb-unit

include \$(PROJ_HOME)/hdl-tools/common.mk

\$(COMPILE): ${COMPONENT_NAME}.sv
EOF

echo "Creating ${BOLD}${COMPONENT_NAME}.qip${NORM}..."
cat > ${COMPONENT_NAME}.qip <<EOF
set_global_assignment -name SYSTEMVERILOG_FILE [file join \$::quartus(qip_path) "${COMPONENT_NAME}.sv"]
EOF

echo "Creating ${BOLD}${COMPONENT_NAME}.sv${NORM}..."
cat > ${COMPONENT_NAME}.sv <<EOF
module ${LIBRARY}_${COMPONENT_NAME}#(
    parameter int A_NBITS,
    parameter int B_NBITS
  )(
    input  logic                        clk_in,
    input  logic[A_NBITS-1 : 0]         a_in,
    input  logic[B_NBITS-1 : 0]         b_in,
    output logic[A_NBITS+B_NBITS-1 : 0] x_out
  );
  always_ff @(posedge clk_in) begin
    x_out <= a_in * b_in;
  end
endmodule
EOF

echo "Creating ${BOLD}README.md${NORM}..."
cat > README.md <<EOF
## ${COMPONENT_NAME}
You can git submodule this repo to provide a variable-width multiplier.

To run the tests:

    make test
EOF

echo "Creating ${BOLD}tb-unit/Makefile${NORM}..."
mkdir tb-unit
cat >> tb-unit/Makefile <<EOF
TESTBENCH := ${COMPONENT_NAME}_tb
LIBS := ${LIBRARY}

include \$(PROJ_HOME)/hdl-tools/common.mk

\$(COMPILE): \$(TESTBENCH:%=%.sv)
EOF

echo "Creating ${BOLD}tb-unit/${COMPONENT_NAME}_tb.sv${NORM}..."
cat > tb-unit/${COMPONENT_NAME}_tb.sv <<EOF
\`timescale 1ps / 1ps

module ${COMPONENT_NAME}_tb#(
    parameter int A_NBITS,
    parameter int B_NBITS,
    parameter int SEED = 23
  );

  localparam int CLK_PERIOD = 10;
  \`include "clocking-util.svh"

  localparam string NAME = \$sformatf("${COMPONENT_NAME}_tb(A_NBITS=%0d, B_NBITS=%0d, SEED=%0d)", A_NBITS, B_NBITS, SEED);
  \`include "svunit-util.svh"

  localparam int LOG2_ITERATIONS = 17;  // 2**17 ~ 100,000

  typedef logic[A_NBITS-1 : 0]         A;
  typedef logic[B_NBITS-1 : 0]         B;
  typedef logic[A_NBITS+B_NBITS-1 : 0] X;

  A a;
  B b;
  X x;

  ${LIBRARY}_${COMPONENT_NAME}#(A_NBITS, B_NBITS) uut(sysClk, a, b, x);

  task testMultiply(A numA, B numB);
    a = numA;
    b = numB;
    @(posedge sysClk); #1;
    \`FAIL_UNLESS(x == numA * numB);
  endtask

  task setup();
    svunit_ut.setup();
    a = 'X;
    b = 'X;
    @(posedge sysClk);
  endtask

  task teardown();
    svunit_ut.teardown();
  endtask

  \`SVUNIT_TESTS_BEGIN
    // Sanity-checks
    \`FATAL_IF(A_NBITS < 2, ("This testbench requires A_NBITS >= 2"));
    \`FATAL_IF(B_NBITS < 2, ("This testbench requires B_NBITS >= 2"));
    \`FATAL_IF(A_NBITS + B_NBITS > 32, ("This testbench requires (A_NBITS + B_NBITS) <= 32"));

    // Try giving the multiplier a selection of values, and verify the result
    \`SVTEST(verify_multiply)
      if (A_NBITS + B_NBITS > LOG2_ITERATIONS) begin
        // There are too many possible input values to try them all, so try some random numbers
        const automatic int dummy = \$urandom(SEED);  // seed RNG
        for (int i = 0; i < 2**LOG2_ITERATIONS; i = i + 1) begin
          testMultiply(\$urandom(), \$urandom());
        end
      end else begin
        // There are a manageable number of pairs of values to try, so just do them all
        for (int numA = 0; numA < 2**A_NBITS; numA = numA + 1) begin
          for (int numB = 0; numB < 2**B_NBITS; numB = numB + 1) begin
            testMultiply(numA, numB);
          end
        end
      end
    \`SVTEST_END
  \`SVUNIT_TESTS_END
endmodule
EOF

echo "Creating ${BOLD}tb-unit/sim.do${NORM}..."
cat > tb-unit/sim.do <<EOF
source "\$::env(PROJ_HOME)/hdl-tools/common.do"

proc do_test {gui} {
  if {\$gui} {
    vsim_run \$::env(TESTBENCH) "-gSEED=23 -gA_NBITS=16 -gB_NBITS=16"

    add wave      dispClk

    add wave -div "Input Side"
    add wave -uns uut/a_in
    add wave -uns uut/b_in

    add wave -div "Output Side"
    add wave -uns uut/x_out

    gui_run 160 65 0 10 0 32 70
  } else {
    set SEED [clock seconds]
    foreach B_NBITS {2 4 8 16} {
      cli_run "-gSEED=\$SEED -gA_NBITS=16 -gB_NBITS=\$B_NBITS"
    }
  }
}
EOF
