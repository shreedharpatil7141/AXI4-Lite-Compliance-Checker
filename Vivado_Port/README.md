# AXI4-Lite Compliance Checker — AMD Vivado 2026.1 / XSim Port

This directory contains the verified AMD Vivado 2026.1 / XSim compatibility port of the **DUT-Agnostic AXI4-Lite Protocol Compliance Checker with Latency Injection and Mutation-Based Evaluation**.

All source modifications are completely contained within this `Vivado_Port/` folder. The original golden source code in `Design/` and `TB/` remains untouched.

---

## 1. Directory Structure

```text
Vivado_Port/
├── Design/                   # Ported RTL sources (axi4_lite_ram, axi4_lite_gpio, dut_sel, etc.)
│   ├── axi4_lite_gpio.sv
│   ├── axi4_lite_ram.sv
│   ├── axi4_lite_ram_mut.sv
│   ├── axi4_lite_ram_mutlib.sv
│   ├── design.sv
│   ├── dut_sel.sv
│   └── interface.sv
├── TB/                       # Ported Testbench sources
│   ├── assertions.sv         # Hardened SVA properties with explicit clocking & per-property disable
│   ├── environment.sv        # Synchronous transaction drain loop
│   ├── coverage.sv
│   ├── driver.sv
│   ├── fault_tasks.sv
│   ├── generator.sv
│   ├── gpio_model.sv
│   ├── latency_injector.sv
│   ├── monitor.sv
│   ├── mutant_tasks.sv
│   ├── scoreboard.sv
│   ├── test.sv
│   ├── testbench.sv
│   ├── transaction.sv
│   └── violation_monitor.sv
├── scripts/                  # Vivado batch execution scripts
│   ├── compile_xsim.bat      # Runs xvlog on Design and TB
│   ├── elaborate_xsim.bat    # Runs xelab to generate axi4l_sim snapshot
│   ├── run_xsim.bat          # Generic xsim runner passing plusargs
│   ├── run_regression_xsim.bat # Executes full multi-stage regression
│   └── run_mutants_xsim.bat  # Executes mutation testing checks
├── COMPATIBILITY_AUDIT.md    # Detailed compatibility report and Xcelium vs XSim matrix
└── README.md                 # This file
```

---

## 2. Quick Start (Running Under Vivado XSim)

### Option A: Run Full Automated Regression
Run the complete regression suite (14-test baseline on RAM, coverage closure, 14-test regression on GPIO, and 9 negative tests):

```cmd
cd "c:\AXI4-Lite Compliance Checker\Vivado_Port"
scripts\run_regression_xsim.bat
```

### Option B: Step-by-Step Manual Invocation

1. **Compile SystemVerilog sources:**
   ```cmd
   scripts\compile_xsim.bat
   ```
   *(Or run directly: `xvlog -sv -i Design Design/design.sv -i TB -i Design TB/testbench.sv`)*

2. **Elaborate simulation snapshot:**
   ```cmd
   scripts\elaborate_xsim.bat
   ```
   *(Or run directly: `xelab -debug typical tb -s axi4l_sim`)*

3. **Run specific simulation campaigns:**

   - **Baseline 14-Test Regression (RAM DUT):**
     ```cmd
     scripts\run_xsim.bat
     ```

   - **Coverage-Directed Test Selection (Closure):**
     ```cmd
     scripts\run_xsim.bat "-testplusarg" "TEST=closure"
     ```

   - **Secondary Peripheral DUT (GPIO):**
     ```cmd
     scripts\run_xsim.bat "-testplusarg" "DUT=gpio"
     ```

   - **Full Negative Suite (9 Defect Injections):**
     ```cmd
     scripts\run_xsim.bat "-testplusarg" "NEG=100"
     ```

   - **Mutation Classifier Logic Verification:**
     ```cmd
     scripts\run_xsim.bat "-testplusarg" "MUTCLASSCHECK=1"
     ```

   - **Individual Mutant Run (e.g., M01):**
     ```cmd
     scripts\run_xsim.bat "-testplusarg" "DUT=rtlmut" "-testplusarg" "MUTID=1"
     ```

---

## 3. Verified Experimental Results in Vivado XSim 2026.1

| Test Campaign | Command / Plusarg | Tests | Result | Measured Cycles | Coverage Hit |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Baseline Regression (RAM)** | Default (`TEST=regress`) | 14 | **14 / 14 PASS** | 10,653 cycles | 49 / 49 (100.0%) |
| **Coverage Closure** | `TEST=closure` | 6 | **6 / 6 PASS** | 6,336 cycles | 49 / 49 (100.0%) |
| **Peripheral Portability (GPIO)** | `DUT=gpio` | 14 | **14 / 14 PASS** | 10,605 cycles | 49 / 49 (100.0%) |
| **Negative Protocol Injections** | `NEG=100` | 9 | **9 / 9 DETECTED** | 529.5 cycles | 0 false positives |
| **Mutation Classifier Checks** | `MUTCLASSCHECK=1` | 10 cases | **ALL PASS** | 4.5 cycles | N/A |

### Cycle Reduction Calculation:
$$\text{Reduction} = \frac{10,653 - 6,336}{10,653} \times 100\% = 40.52\%$$

---

## 4. Key Compatibility Changes

1. **Default Disable iff Elimination**: Replaced unsupported global `default disable iff (!vif.ARESETN);` (`[XSIM 43-3980]`) with explicit per-property clauses (`disable iff (!vif.ARESETN)`).
2. **Explicit Clocking Arguments on SVA System Functions**: SVA properties calling `$stable` and `$past` now explicitly pass `@(posedge vif.ACLK)` to resolve `[XSIM 43-4463]`.
3. **Synchronous Wait Handling in Environment**: Replaced class member task argument sensitivity `wait (checked >= target);` with synchronous edge polling `while (checked < target) @(posedge drv.vif.ACLK);` to resolve `[XSIM 43-4328]` and `[XSIM 43-3980]`.
4. **4-State Power-On Robustness**: Hardened reset assertions A12 and A12b against uninitialized `1'bx` values at $t=0$ by using 4-state exact comparisons (`=== 1'b0` and `!== 1'b1`).
