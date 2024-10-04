package legendary_tracker

import "core:crypto"
import "core:encoding/csv"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:os"

csv_row_to_structs :: proc(row: []string) -> (wins: []Win, scheme: Scheme) {
	context.random_generator = crypto.random_generator()
	scheme.id = uuid.generate_v4()
	scheme.name = row[0]

	arr: [dynamic]Win
	for v, i in row[1:] {
		//fmt.printfln("'%v'", v)
		if v != "" {
			log.debug("Making Win struct")
			win: Win
			if i < 4 {
				win.face_card = false
			} else {
				win.face_card = true
			}

			win.extra_twist = i % 4
			win.scheme = scheme.id
			win.id = uuid.generate_v4()

			append(&arr, win)
		}
	}

	log.infof("%#v", arr)
	wins = arr[:]
	return
}

import_csv :: proc(path: string) -> (wins: []Win, schemes: []Scheme, ok: bool) {
	file, err := os.open(path)
	defer os.close(file)

	if err != os.ERROR_NONE {
		log.error("failed to open csv file", err)
		return
	}

	stream := os.stream_from_handle(file)

	reader: csv.Reader
	csv.reader_init(&reader, stream, context.temp_allocator)

	wins_arr: [dynamic]Win
	schemes_arr: [dynamic]Scheme

	for row, i in csv.iterator_next(&reader) {
		if i == 0 do continue
		fmt.println(i, " | ", row)
		row_wins, row_scheme := csv_row_to_structs(row)
		fmt.println(row_wins, row_scheme, wins[:])
		append(&wins_arr, ..row_wins)
		append(&schemes_arr, row_scheme)
	}

	wins = wins_arr[:]
	schemes = schemes_arr[:]
	ok = true

	log.infof("\n\n%#v\n\n%#v\n\n", wins, schemes)
	return
}
