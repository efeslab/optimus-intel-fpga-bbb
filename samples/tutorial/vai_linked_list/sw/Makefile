include ../../common/sw/common_include.mk

# Primary test name
TEST = linked_list_nompf

# Build directory
OBJDIR = obj
CFLAGS += -I./$(OBJDIR) -DASE_REGION
CPPFLAGS += -I./$(OBJDIR)

# Files and folders
SRCS = $(TEST).c $(BASE_FILE_SRC)
OBJS = $(addprefix $(OBJDIR)/,$(patsubst %.c,%.o,$(SRCS)))

# Targets
all: $(TEST) $(TEST)_ase

# AFU info from JSON file, including AFU UUID
AFU_JSON_INFO = $(OBJDIR)/afu_json_info.h
$(AFU_JSON_INFO): ../hw/rtl/$(TEST)_cci.json | objdir
	afu_json_mgr json-info --afu-json=$^ --c-hdr=$@
$(OBJS): $(AFU_JSON_INFO)

$(TEST): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(FPGA_LIBS)

$(TEST)_vai: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(FPGA_VAI_LIBS)

$(TEST)_ase: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(ASE_LIBS)

$(TEST)_vai_ase: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(VAI_ASE_LIBS)

$(OBJDIR)/%.o: %.c | objdir
	$(CC) $(CFLAGS) $(VAI_FLAGS) -c $< -o $@

clean:
	rm -rf $(TEST) $(TEST)_ase $(OBJDIR)

objdir:
	@mkdir -p $(OBJDIR)

.PHONY: all clean
