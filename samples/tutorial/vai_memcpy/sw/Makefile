include ../../common/sw/common_include.mk

# Primary test name
TEST = cci_memcpy

# Build directory
OBJDIR = obj
CFLAGS += -I./$(OBJDIR)
CPPFLAGS += -I./$(OBJDIR)

# Files and folders
SRCS = $(TEST).c
OBJS = $(addprefix $(OBJDIR)/,$(patsubst %.c,%.o,$(SRCS)))

# Targets (build only $(TEST)_ase by default)
all: $(TEST) $(TEST)_ase

$(TEST): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(FPGA_LIBS)

$(TEST)_ase: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(ASE_LIBS)

$(OBJDIR)/%.o: %.c | objdir
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(TEST) $(TEST)_ase $(OBJDIR)

objdir:
	@mkdir -p $(OBJDIR)

.PHONY: all clean
