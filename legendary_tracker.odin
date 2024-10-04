package legendary_tracker

import "core:crypto"
import "core:encoding/csv"
import "core:encoding/json"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/windows"

Win :: struct {
	scheme:      uuid.Identifier,
	id:          uuid.Identifier,
	extra_twist: int,
	face_card:   bool,
}

Scheme :: struct {
	id:        uuid.Identifier,
	name:      string,
	expansion: string,
}

capitalize :: proc(str: string) -> string {
	builder := strings.builder_make(context.temp_allocator)

	words := strings.split(str, " ", context.temp_allocator)

	for word in words {
		strings.write_string(&builder, strings.to_pascal_case(word, context.temp_allocator))
		strings.write_string(&builder, " ")
	}

	return strings.to_string(builder)
}

print_scheme :: proc(scheme: Scheme, wins: []Win, name_col_width: int) -> string {
	builder := strings.builder_make()


	strings.write_string(
		&builder,
		strings.center_justify(
			capitalize(scheme.name),
			name_col_width,
			" ",
			context.temp_allocator,
		),
	)

	twist_set: bit_set[0 ..< 4]
	face_set: bit_set[0 ..< 4]

	for win in wins {
		if win.scheme == scheme.id {
			if win.face_card {
				face_set += bit_set[0 ..< 4]{win.extra_twist}
			} else {
				twist_set += bit_set[0 ..< 4]{win.extra_twist}
			}}
	}

	strings.write_string(
		&builder,
		fmt.aprintf(
			"| %v   | %v   | %v   | %v   | %v   | %v   | %v   | %v   |",
			print_bool(0 in twist_set),
			print_bool(1 in twist_set),
			print_bool(2 in twist_set),
			print_bool(3 in twist_set),
			print_bool(0 in face_set),
			print_bool(1 in face_set),
			print_bool(2 in face_set),
			print_bool(3 in face_set),
		),
	)

	return strings.to_string(builder)
}

print_schemes :: proc(schemes: []Scheme, wins: []Win, name_col_width: int) -> string {
	builder := strings.builder_make(context.temp_allocator)

	name_col_string := strings.center_justify("Name", name_col_width, " ", context.temp_allocator)
	strings.write_string(
		&builder,
		fmt.aprintf("%v| +0  | +1  | +2  | +3  | F+0 | F+1 | F+2 | F+3 |\n\n", name_col_string),
	)


	for scheme in schemes {
		strings.write_string(
			&builder,
			fmt.aprintf("%v\n", print_scheme(scheme, wins, name_col_width)),
		)
	}

	return strings.to_string(builder)
}

print_bool :: proc(truthy: bool) -> rune {
	if truthy {
		return '✔'
	} else {
		return ' '
	}
}

csv_row_to_structs :: proc(row: []string) -> (wins: []Win, scheme: Scheme) {
	context.random_generator = crypto.random_generator()
	scheme.id = uuid.generate_v4()
	scheme.name = row[0]

	arr: [dynamic]Win
	for v, i in row[1:] {
		//fmt.printfln("'%v'", v)
		if v == "x" {
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

main :: proc() {
	when ODIN_OS == .Windows {
		windows.SetConsoleOutputCP(windows.CODEPAGE.UTF8)
	}

	log_path := "legendary_tracker.log"
	if !os.exists(log_path) {
		os.write_entire_file(log_path, []byte{})
	}
	log_file, log_file_err := os.open(log_path, 2)

	if log_file_err != os.ERROR_NONE {
		fmt.println("unable to open log file", log_file_err)
	}

	defer os.close(log_file)

	file_logger := log.create_file_logger(log_file)
	console_logger := log.create_console_logger()

	context.logger = log.create_multi_logger(file_logger, console_logger)


	schemes: [dynamic]Scheme
	wins: [dynamic]Win

	for arg, i in os.args {
		if arg == "--import-backup" {
			if i + 1 >= len(os.args) {
				log.error("Need a path")
				return
			}
			log.info("Importing backup", i)
			import_wins, import_schemes, import_ok := import_csv(os.args[i + 1])
			if !import_ok {
				log.error("Failed to import")
				return
			}

			append(&schemes, ..import_schemes)
			append(&wins, ..import_wins)
			save_wins(wins[:])
			save_schemes(schemes[:])
			log.info("Backup successfully imported!")
			return
		}

	}

	loaded_schemes, schemes_ok := load_schemes()
	if !schemes_ok {
		log.error("Unable to load schemes")
		return
	}

	append(&schemes, ..loaded_schemes)

	if len(schemes) == 0 {
		scheme, add_scheme_ok := add_scheme()
		append(&schemes, scheme)
		save_schemes(schemes[:])
		log.debug("Schemes saved")
	}

	longest_scheme_name := schemes[0].name
	for scheme in schemes {
		if len(scheme.name) > len(longest_scheme_name) {
			longest_scheme_name = scheme.name
		}
	}

	log.debugf("Loaded schemes. Longest scheme name: '%v'", longest_scheme_name)

	loaded_wins, wins_ok := load_wins()
	if !wins_ok {
		log.error("Unable to load wins")
		return
	}

	append(&wins, ..loaded_wins)

	log.infof("\n\n%v\n\n", print_schemes(schemes[:], wins[:], len(longest_scheme_name) + 2))

	buf: [1024]byte

	fmt.print("Scheme? ")
	n, err := os.read(os.stdin, buf[:])

	if err != nil {
		log.error("Error reading: ", err)
		return
	}

	input_str := strings.to_lower(strings.split_lines(string(buf[:n]))[0])

	log.infof("\nSearching for: '%v'\n", input_str)
	closest_schemes := get_closest_schemes(schemes[:], input_str)

	selected_scheme, select_ok := select_scheme(closest_schemes[:])
	if !select_ok {
		log.error("Failed to select a scheme")
		return
	}
	log.infof("'%v' selected", selected_scheme.name)

	new_win, add_win_ok := add_win(selected_scheme)
	if (add_win_ok) {
		append(&wins, new_win)
		save_wins(wins[:])
		log.info("Wins updated!")
	} else {
		log.error("Failed to update wins.")
	}

}

add_win :: proc(scheme: Scheme) -> (win: Win, ok: bool = true) {
	log.debug("Adding new win.")
	buf: [1024]byte

	context.random_generator = crypto.random_generator()
	win.id = uuid.generate_v4()
	win.scheme = scheme.id

	fmt.print("How many extra twists? ")
	n: int
	err: os.Errno

	n, err = os.read(os.stdin, buf[:])

	if err != nil {
		log.error("Error reading: ", err)
		ok = false
		return
	}

	win.extra_twist = strconv.parse_int(strings.trim_space(string(buf[:n]))) or_else 0

	buf = [1024]byte{}

	fmt.print("Face card defeated (y/n)? ")

	n, err = os.read(os.stdin, buf[:])

	if err != nil {
		log.error("Error reading: ", err)
		ok = false
		return
	}

	face := strings.trim_space(string(buf[:n]))
	if face == "y" {
		win.face_card = true
	} else if face == "n" {
		win.face_card = false
	} else {
		log.error("Invalid response (should be y/n):", face)
		ok = false
	}
	return
}

save_wins :: proc(wins: []Win) -> bool {
	data, err := json.marshal(wins, {}, context.temp_allocator)

	if err != nil {
		log.error("Unable to marshal wins", err)
		return false
	}
	return os.write_entire_file("wins.json", data)
}

load_wins :: proc() -> (wins: []Win, ok: bool) {
	path := filepath.join([]string{get_dir(), "wins.json"})
	db_file, err := os.open(path)
	defer os.close(db_file)

	if err != nil {
		log.error("Failed to open wins file", err)

		empty: string = "[]"
		write_ok := os.write_entire_file("wins.json", transmute([]u8)empty)

		if !write_ok {
			ok := false
			return
		}
		return load_wins()
	}

	data, read_ok := os.read_entire_file(db_file, context.temp_allocator)

	if !read_ok {
		log.error("Failed to read wins file:", read_ok)
		ok = false
		return
	}

	unmarshall_err := json.unmarshal(data, &wins)

	if unmarshall_err != nil {
		log.error("Failed to unmarshall wins file", unmarshall_err)
		ok = false
		return
	}
	ok = true
	return
}

add_scheme :: proc() -> (scheme: Scheme, ok: bool = true) {
	log.debug("Adding new scheme.")
	buf: [1024]byte

	context.random_generator = crypto.random_generator()
	scheme.id = uuid.generate_v4()

	fmt.print("Scheme name? ")
	n: int
	err: os.Errno

	n, err = os.read(os.stdin, buf[:])

	if err != nil {
		log.error("Error reading: ", err)
		ok = false
		return
	}

	scheme.name = strings.to_lower(strings.split_lines(string(buf[:n]))[0])

	buf = [1024]byte{}

	fmt.print("Expansion? ")
	n, err = os.read(os.stdin, buf[:])

	if err != nil {
		log.debug("Error reading: ", err)
		ok = false
		return
	}

	scheme.expansion = strings.to_lower(strings.split_lines(string(buf[:n]))[0])

	return
}

select_scheme :: proc(schemes: []Scheme) -> (selected_scheme: Scheme, ok: bool = true) {
	log.debug("Selecting scheme")
	for scheme, i in schemes {
		log.infof("\t%v: %v", i, scheme.name)
	}

	new_scheme_opt := len(schemes)

	log.infof("\n\t%v: add new scheme", new_scheme_opt)

	buf := [1024]byte{}

	fmt.print("\nSelection? ")
	n, err := os.read(os.stdin, buf[:])

	if err != nil {
		log.error("Error reading: ", err)
		ok = false
		return
	}

	selection := strings.trim_space(string(buf[:n]))

	for scheme, i in schemes {
		index := fmt.tprintf("%v", i)
		if selection == index {
			selected_scheme = scheme
			return
		}
	}

	if selection == fmt.tprintf("%v", new_scheme_opt) {
		selected_scheme, ok = add_scheme()

		all_schemes, load_ok := load_schemes()
		if !load_ok do panic("no schemes could be loaded which should never happen this late in execution")

		arr: [dynamic]Scheme
		defer delete(arr)
		append(&arr, ..all_schemes)
		append(&arr, selected_scheme)
		save_schemes(arr[:])

		return
	}

	log.errorf("Invalid selection: '%v'", selection)

	ok = false
	return
}

save_schemes :: proc(schemes: []Scheme) -> bool {
	data, err := json.marshal(schemes, {}, context.temp_allocator)

	if err != nil {
		log.error("Unable to marshal schemes", err)
		return false
	}
	return os.write_entire_file("schemes.json", data)
}

get_dir :: proc() -> string {
	dir, file := filepath.split(#file)
	return dir
}
load_schemes :: proc() -> (schemes: []Scheme, ok: bool) {
	path := filepath.join([]string{get_dir(), "schemes.json"})

	db_file, err := os.open(path)
	defer os.close(db_file)

	if err != nil {
		log.error("Failed to open schemes file", err)

		empty: string = "[]"
		write_ok := os.write_entire_file("schemes.json", transmute([]u8)empty)

		if !write_ok {
			ok := false
			return
		}
		return load_schemes()
	}

	data, read_ok := os.read_entire_file(db_file, context.temp_allocator)

	if !read_ok {
		log.error("Failed to read schemes file:", read_ok)
		ok = false
		return
	}

	unmarshall_err := json.unmarshal(data, &schemes)

	if unmarshall_err != nil {
		log.error("Failed to unmarshall schemes file", unmarshall_err)
		ok = false
		return
	}
	ok = true
	return
}

get_closest_schemes :: proc(schemes: []Scheme, input_str: string) -> (closest: [dynamic]Scheme) {
	Ordered :: struct {
		scheme: Scheme,
		score:  f32,
	}

	distances: [dynamic]Ordered
	if len(schemes) == 0 {
		return
	}

	for scheme, i in schemes {
		score: f32 = 1 / f32(strings.levenshtein_distance(input_str, scheme.name)) + 1
		if strings.contains(scheme.name, input_str) {
			score *= 2
		}
		if strings.has_prefix(scheme.name, input_str) {
			score *= 2
		}


		append(&distances, Ordered{scheme = scheme, score = score})
	}

	ordered := distances[:]
	slice.sort_by(ordered, proc(a, b: Ordered) -> bool {
		return a.score < b.score
	})
	slice.reverse(ordered)


	for index in 0 ..< min(5, len(ordered)) {
		append(&closest, ordered[index].scheme)
	}

	return
}
