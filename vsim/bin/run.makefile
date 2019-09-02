SHELL         = bash
RUN_DIR      := ${PWD}

TESTCASE     := ${RUN_DIR}/../../riscv-tools/riscv-tests/isa/generated/rv32ui-p-addi
DUMPWAVE     := 1

VSRC_DIR     := ${RUN_DIR}/../install/rtl
VTB_DIR      := ${RUN_DIR}/../install/tb
TESTNAME     := $(notdir $(patsubst %.dump,%,${TESTCASE}.dump))
TEST_RUNDIR  := ${TESTNAME}

TB_C_FILES    := ${RUN_DIR}/../install/tb/sim.cpp
RTL_V_FILES		:= $(wildcard ${VSRC_DIR}/*/*.v)
TB_V_FILES		:= $(wildcard ${VTB_DIR}/*.v)
TOP_MODULE    := tb_top

OBJDIR         = obj
OBJ            = sim

# The following portion is depending on the EDA tools you are using, Please add them by yourself according to your EDA vendors

SIM_TOOL      := verilator

SIM_OPTIONS   := -cc --exe --Mdir $(OBJDIR) +incdir+$(VSRC_DIR)/core +incdir+$(VSRC_DIR)/perips \
	 --top-module $(TOP_MODULE) \
	 -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -DFPGA_SOURCE
SIM_EXEC      := ${RUN_DIR}/$(OBJDIR)/Vtb_top

WAV_TOOL      := #To-ADD: to add the waveform tool
WAV_OPTIONS   := #To-ADD: to add the waveform tool options 
WAV_PFIX      := #To-ADD: to add the waveform file postfix

all: run

compile.flg: ${RTL_V_FILES} ${TB_V_FILES} ${TB_C_FILES}
	@-rm -rf compile.flg
	${SIM_TOOL} ${SIM_OPTIONS} ${RTL_V_FILES} ${TB_V_FILES} ${TB_C_FILES} ; \
    make -C $(OBJDIR) -f V$(TOP_MODULE).mk
	touch compile.flg

compile: compile.flg 

wave: 
	gvim -p ${TESTCASE}.spike.log ${TESTCASE}.dump &
	${WAV_TOOL} ${WAV_OPTIONS} & 

run: compile
	rm -rf ${TEST_RUNDIR}
	mkdir ${TEST_RUNDIR}
	cd ${TEST_RUNDIR}; ${SIM_EXEC} +DUMPWAVE=${DUMPWAVE} +TESTCASE=${TESTCASE} |& tee ${TESTNAME}.log; cd ${RUN_DIR}; 


.PHONY: run clean all 

