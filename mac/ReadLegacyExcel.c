#include <stdio.h>
#include "xls.h"

static void write_field(const char *value) {
    if (!value) return;
    putchar('"');
    for (; *value; ++value) {
        if (*value == '"') putchar('"');
        putchar(*value);
    }
    putchar('"');
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    xlsWorkBook *book = xls_open_file(argv[1], "UTF-8", NULL);
    if (!book) return 1;

    xlsWorkSheet *sheet = book->sheets.count ? xls_getWorkSheet(book, 0) : NULL;
    int result = 1;
    if (sheet && xls_parseWorkSheet(sheet) == LIBXLS_OK) {
        for (unsigned row = 0; row <= sheet->rows.lastrow; ++row) {
            for (unsigned column = 0; column <= sheet->rows.lastcol; ++column) {
                if (column) putchar(',');
                xlsCell *cell = xls_cell(sheet, row, column);
                if (cell) write_field(cell->str);
            }
            putchar('\n');
        }
        result = fflush(stdout) == EOF;
    }
    if (sheet) xls_close_WS(sheet);
    xls_close_WB(book);
    return result;
}
