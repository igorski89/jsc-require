CC=clang
CFLAGS=-std=c99 -fobjc-arc -lobjc -framework Foundation -framework JavaScriptCore
EXECUTABLE=jsc-require
SOURCES=main.m

compile: $(SOURCES)
		$(CC) $(CFLAGS) -o $(EXECUTABLE) $(SOURCES)

clean:
		rm -rf $(EXECUTABLE)

run: compile
		./$(EXECUTABLE) $(ARGS)

debug: compile
		lldb $(EXECUTABLE) -- $(ARGS)

all: compile