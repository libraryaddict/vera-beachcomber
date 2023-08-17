since r19668;

import <vprops.ash>;
import <BeachComberData.ash>

// ***************************
//          To Do            *
// ***************************

// Support creating a driftwood beach comb from a piece of driftwood?

// ***************************
//        Requirements       *
// ***************************

// A Beach Comb or a driftwood beach comb
// You can have it equipped.
// Otherwise it must be in a place that "retrieve_item" can find it.

item beach_comb = $item[ Beach Comb ];
item driftwood_beach_comb = $item[ driftwood beach comb ];
item piece_of_driftwood = $item[ piece of driftwood ];

// ***************************
//       Configuration       *
// ***************************

typedef string [int] string_list;
typedef boolean [string] string_set;

//-------------------------------------------------------------------------
// All of the configuration variables have default values, which apply
// to any character who does not override the variable using the
// appropriate property.
//
// You can edit the default here in the script and it will apply to all
// characters which do not override it.
//
// define_property( PROPERTY, TYPE, DEFAULT )
// define_property( PROPERTY, TYPE, DEFAULT, COLLECTION )
// define_property( PROPERTY, TYPE, DEFAULT, COLLECTION, DELIMITER )
//
// Otherwise, you can change the value for specific characters in the gCLI:
//
//     set PROPERTY=VALUE
//
// Both DEFAULT and a property VALUE will be normalized
//
// All properties used directly by this script start with "VBC."
//-------------------------------------------------------------------------

// How to prioritize beach squares to comb
//
// W	a beached whale
// ?	an unclassifiable square
// C	a sand castle
// r	rough sand
// t	rough sand with a twinkle
// c	combed sand
// H	a beach head
//
// There is a fixed set of 11 beach heads, and if you want to visit, you
// can do that manually, so they are not prioritized by default. If you
// want a random buff rather than items, add them.
//
// We do not expect any unidentifiable square. If KoLmafia finds a
// square it cannot classify, it will log it in the gCLI and session log
// and return a "?". This script assumes such squares are worth visiting.

string_list priorities = define_property( "VBC.Priorities", "string", "W,?,t,r,c", "list" ).to_string_list( "," );

// Square picking strategy:
//
// random	pick randomly from all squares containing the highest priority
// twinkle	comb all patches of rough sand with a twinkle within a beach
//		before moving to another section

string pick_strategy = define_property( "VBC.PickStrategy", "string", "random" );

// ***************************
//        Validatation       *
// ***************************

static string_set priority_options = $strings[
    ?,
    C,
    H,
    W,
    c,
    r,
    t,
];

static string_set strategy_options = $strings[
    random,
    twinkle
];

void validate_configuration()
{
    boolean valid = true;

    print( "Validating configuration." );

    boolean tseen = false;
    boolean rseen = false;
    boolean cseen = false;

    foreach index, priority in priorities {
	if ( !( priority_options contains priority ) ) {
	    print( "VBC.Priorities: '" + priority + "' is not a valid square type.", "red" );
	    valid = false;
	} else if ( priority == "r" ) {
	    rseen = true;
	} else if ( priority == "c" ) {
	    cseen = true;
	} else if ( priority == "t" ) {
	    tseen = true;
	}
    }

    // Always put 't', 'r' and 'c' at the end if otherwise not specified
    if ( valid ) {
	if ( !tseen ) {
	    print( "VBC.Priorities: adding 't'." );
	    priorities[ count( priorities ) ] = "t";
	}
	if ( !rseen ) {
	    print( "VBC.Priorities: adding 'r'." );
	    priorities[ count( priorities ) ] = "r";
	}
	if ( !cseen ) {
	    print( "VBC.Priorities: adding 'c'." );
	    priorities[ count( priorities ) ] = "c";
	}
    }

    if ( !( strategy_options contains pick_strategy ) ) {
	print( "VBC.PickStrategy: '" + pick_strategy + "' is invalid.", "red" );
	valid = false;
    }

    if ( !valid ) {
	abort( "Correct those errors and try again." );
    }

    print( "All is well!" );
}

void print_help()
{
    string spaces = "&nbsp;&nbsp;&nbsp;&nbsp;";
    print("BeachComber PARAM...");
    print_html(spaces + "<b>free</b>: comb beach using only free wanders" );
    print_html(spaces + "<b>all</b>: comb beach using free wanders and all remaining turns" );
    print_html(spaces + "<b>NUMBER</b>: comb beach using free wanders and specified number of turns" );
    print_html("");
    print_html(spaces + "<b>random</b>: visit random sections of the beach" );
    // print_html(spaces + "<b>rare</b>: visit sections of the beach with known rare tiles" );
    print_html(spaces + "<b>spade</b>: methodically visit successive sections of the beach" );
    print_html(spaces + "<b>minutes=NUMBER</b>: visit specific section of the beach" );
    // print_html("");
    // print_html(spaces + "<b>twinkle</b>: comb all twinkly tiles" );
    // print_html(spaces + "<b>known</b>: comb only known rare tiles" );
    // print_html(spaces + "(the above will comb rough sand if there are no better candiates)" );
    print_html("");
    print_html(spaces + "<b>help</b>: print this message" );
    print_html(spaces + "<b>data</b>: load, analyze, and print tile data, and then exit" );
}

// Mode for selecting sections of the beach to visit
// 
// random       Walk randomly down the beach and comb tiles
// rare         Walk to beach sections that are known to have rare tiles.
// spade        Walk to next unspaded section of the beach
// minutes=N    Walk N minutes down the beach and comb only that square.
//
// Strategy for picking tiles to comb in a beach section before wandering somewhere else
//
// twinkle      Comb all tiles with a twinkle in a beach section
// known        Comb all uncombed rare tiles (or the first tile with a twinkle)
//
// Specification of how many turns to spend combing tiles
//
// free         Only the (up to) 11 available daily free visits
// all          All available turns
// NNN          free turns (if any) + NNN non-free turns
//
// Interactions:
//
// If "spade", strategy will be "twinkle": comb all twinkles before
// moving to the (numerically) next section of the beach.
//
// If minutes=N, only the specified section of the beach will be visited.
// As many turns as necessary will be used to comb all the "twinkle" tiles.
// After that is completed, execution ends; we will not visit another section.

string mode = "rare";
string strategy = "known";
int turns = 0;
int beach = 0;
boolean completed = false;

void parse_parameters(string... parameters)
{
    boolean bogus = false;
    foreach n, param in parameters {
	if (param == "help") {
	    print_help();
	    exit;
	}
	switch (param) {
	case "":
	    continue;
	case "free":
	    turns = 0;
	    continue;
	case "all":
	    turns = my_adventures();
	    continue;
	case "data":
	    mode = "data";
	    continue;
	case "random":
	    mode = "random";
	    pick_strategy = "twinkle";
	    continue;
	case "rare":
	    mode = "rare";
	    pick_strategy = "twinkle";
	    continue;
	case "spade":
	    mode = "spade";
	    pick_strategy = "twinkle";
	    continue;
	}

	if (param.is_integer()) {
	    turns = param.to_int();
	    continue;
	}

	if (param.starts_with("minutes=")) {
	    int index = param.index_of("=");
	    string value = param.substring(index + 1);
	    beach = value.is_integer() ? value.to_int() : 0;
	    if (beach == 0) {
		print("How many minutes?", "red");
		bogus = true;
		continue;
	    }
	    if (beach < 1 || beach > 10000) {
		print("You can wander from 1 to 10000 minutes down the beach.", "red");
		bogus = true;
		continue;
	    }
	    mode = "beach";
	    pick_strategy = "twinkle";
	    continue;
	}

	print("I don't understand what '" + param + "' means", "red");
	bogus = true;
	continue;
    }

    if (bogus) {
	print_help();
	exit;
    }
}

// ***************************
//       Data Structures     *
// ***************************

// This script depends on KoLmafia's built-in parsing of the beach when
// you visit it.
//
// _beachMinutes	int
// _beachLayout		ROW:LAYOUT[,...]

int get_minutes()
{
    return get_property( "_beachMinutes" ).to_int();
}

string get_layout()
{
    return get_property( "_beachLayout" );
}

string set_squares( string squares )
{
    return set_property( "_beachLayout", squares );
}

// These are the codes that KoLmafia returns for various kinds of beach
// squares

static string [string] code_to_type = {
    "t" : "rough sand with a twinkle",
    "r" : "rough sand",
    "c" : "combed sand",
    "C" : "a sand castle",
    "H" : "a beach head",
    "W" : "a beached whale",
    "?" : "unknown",
};

static string [string] type_to_code = {
    "rough sand with a twinkle" : "t",
    "rough sand" : "r",
    "combed sand" : "c",
    "a sand castle" : "C",
    "a beach head" : "H",
    "a beached whale" : "W",
    "unknown" : "?",
};

// This data structure is an easier to use representation of KoLmafia's
// string representation in _beachLayout. It maps row number (an int) to
// 10-character string of squares, coded as above

typedef string [int] beach_layout;

// Function to convert a string compaticle with the _beachLayout
// property to a beach_layout map

beach_layout to_beach_layout( string squares )
{
    beach_layout layout;
    foreach i, row_data in squares.split_string( "," ) {
	int colon = row_data.index_of( ":" );
	if ( colon != -1 ) {
	    int row = row_data.substring( 0, colon ).to_int();
	    string squares = row_data.substring( colon + 1 );
	    layout[ row ] = squares;
	}
    }
    return layout;
}

// Function to convert beach layout map into a string compatible with
// the _beachLaout property

string to_string( beach_layout layout )
{
    buffer value;
    foreach row, squares in layout {
	if ( value.length() > 0 ) {
	    value.append( "," );
	}
	value.append( row );
	value.append( ":" );
	value.append( squares );
    }
    return value.to_string();
}

beach_layout get_beach_layout()
{
    return get_layout().to_beach_layout();
}

void set_beach_layout( beach_layout layout )
{
    set_property( "_beachLayout", layout );
}

string square_at( beach_layout layout, coords c )
{
    return layout[ c.row ].char_at( c.column );
}

// This data structure contains all of the squares of a beach_layout
// split into sorted lists of coords of a particular coded type, mapping
// from code to list of coords

typedef coords_list [string] sorted_beach_map;

sorted_beach_map sort_beach( int beach, beach_layout layout )
{
    sorted_beach_map map;

    foreach row, squares in layout {
	for ( int col = 0; col < 10; ++col ) {
	    coords c = new coords( beach, row, col );
	    string ch = squares.char_at( col );
	    coords_list clist = map[ ch ];
	    clist.add_tile(c);
	    map[ ch ] = clist;
	}
    }

    foreach ch, clist in map {
	print( count( clist ) + " squares in beach " + beach + " contain " + code_to_type[ ch ] );
    }

    return map;
}

sorted_beach_map sort_beach()
{
    return sort_beach( get_minutes(), get_beach_layout() );
}

coords_list extract_twinkles(sorted_beach_map map) {
    coords_list twinkles;
    twinkles.add_tiles(map["W"]);
    twinkles.add_tiles(map["t"]);
    return twinkles;
}

void save_new_twinkles(coords_list twinkles) {
    foreach key, c in twinkles {
	if (rare_tiles contains key ||
	    rare_tiles_new contains key ||
	    uncommon_tiles contains key ||
	    uncommon_tiles_new contains key) {
	    // We've seen this twinkle before
	    continue;
	}
	// Previously unobserved.
	twinkle_tiles.add_tile(c);
    }
}

void save_visited_tile(coords tile, string tile_type) {
    int key = tile.to_key();
    switch (tile_type) {
    case "rare":
	// If this was a known rare tile, mark it as seen
	if (rare_tiles contains key) {
	    rare_tiles_seen.add_tile(tile);
	} else {
	    rare_tiles_new.add_tile(tile);
	}
	return;
    case "uncommon":
	// If we thought this was a rare tile, oops!
	if (rare_tiles contains key) {
	    rare_tiles.remove_tile(tile);
	    rare_tiles_errors.add_tile(tile);
	} else if (uncommon_tiles contains key) {
	    // Been there, done that.
	} else {
	    uncommon_tiles_new.add_tile(tile);
	}
	return;
    default:
	// If we thought this was a rare tile, oops!
	if (rare_tiles contains key) {
	    rare_tiles.remove_tile(tile);
	    rare_tiles_errors.add_tile(tile);
	}
	return;
    }
}

// ***************************
//       Tile Categories     *
// ***************************

// The Wiki uses frequent, infrequent, and scarce.
// I prefer to draw my inspiration from MtG :)

static item_set common_items = $items[ 
    // "Very Commonly"
    driftwood bracelet,
    driftwood pants,
    driftwood hat,
    // "Commonly"
    kelp,
    bunch of sea grapes,
    magenta seashell,
    cyan seashell,
    gray seashell,
    green seashell,
    yellow seashell,
    // "Uncommonly"
    taco shell,
    sea avocado,
    sea carrot,
    sea cucumber,
    // "Rarely"
    beach glass bead,
    coconut shell,
    sea salt crystal,
    sea grease,
    sea jelly,
    sea lace,
    seal tooth,
];

static item_set uncommon_items = $items[ 
    // "Commonly"
    sand dollar,
    dull fish scale,
    // "Uncommonly"
    rough fish scale,
    lucky rabbitfish fin,
    spearfish fishing spear,
    waders,
    // "Rarely"
    pristine fish scale,
    piece of coral,
];

static item_set rare_items = $items[ 
    // "Commonly"
    piece of driftwood,
    // "Rarely"
    cursed pirate cutlass,
    cursed swash buckle,
    cursed tricorn hat,
    // (message in a bottle)
    // "Extremely Rarely"
    meteorite fragment,
    rainbow pearl,
    // (Whale)
];

string categorize_tile(int[item] items)
{
    foreach it in items {
	if (common_items contains it) {
	    return "common";
	}
	if (uncommon_items contains it) {
	    return "uncommon";
	}
	if (rare_items contains it) {
	    return "rare";
	}
    }

    return "unknown";
}

// BeachComberData loaded the set of known tiles into various coords_lists
// Make some maps that let us look up tiles by # of minutes down the beach.

typedef coords_list[int] coords_map;

coords_map rare_tiles_map;
coords_map uncommon_tiles_map;
coords_map twinkles_map;

void populate_tile_maps(boolean verbose)
{
    void add_to_map(coords_map map, coords_list list)
    {
	foreach key, tile in list {
	    int minutes = tile.minute;
	    coords_list mmap = map[minutes];
	    mmap[key] = tile;
	    map[minutes] = mmap;
	}
    }

    rare_tiles_map.add_to_map(rare_tiles);
    rare_tiles_map.add_to_map(rare_tiles_new);
    uncommon_tiles_map.add_to_map(uncommon_tiles);
    uncommon_tiles_map.add_to_map(uncommon_tiles_new);
    twinkles_map.add_to_map(twinkle_tiles);

    if (verbose) {
	print("Beaches with rare tiles: " + count(rare_tiles_map));
	print("Beaches with uncommon tiles: " + count(uncommon_tiles_map));
	print("Beaches with unvisited twinkles: " + count(twinkles_map));
    }
}

// ***************************
//          Strategies       *
// ***************************

// Pick randomly from all squares of the highest priority

coords pick_coords_to_comb( int beach, sorted_beach_map map )
{
    coords pick_index(coords_list clist, int index) {
	if (index < count(clist)) {
	    int i = 0;
	    foreach key, c in clist {
		if (i++ == index) {
		    return c;
		}
	    }
	}
	// This should not be possible
	return new coords(beach, 10, 0);
    }

    coords pick_random(coords_list clist) {
	int range = count(clist);
	return pick_index(clist, range == 1 ? 0 : random( range ));
    }

    coords pick_rare(coords_list clist) {
	foreach key, c in clist {
	    if (rare_tiles contains key ||
		rare_tiles_new contains key) {
		return c;
	    }
	}
	// No known rare tile. Pick a random one.
	return pick_random(clist);
    }

    foreach index, choice in priorities {
	coords_list clist = map[choice];
	if ( count(clist) > 0 ) {
	    return pick_rare( clist );
	}
    }

    // This should not be possible
    return new coords(beach, 10, 0);
}

// ***************************
//          Utilities        *
// ***************************

buffer use_comb()
{
    // Requires GET
    return visit_url( "main.php?comb=1", false );
}

void put_away_comb()
{
    int choice = last_choice();
    if ( choice == 1388 ) {
	run_choice( 5 );
    }
}

int [string] combed_rarities;
int [string] combed_types;
int [item] combed_items;
int combed_meat;
string [int] beachcombings;

beach_layout modify_square( beach_layout layout, coords c, string val )
{
    int row = c.row;
    int column = c.column;

    string squares = layout[ row ];

    buffer modified;
    if ( column > 0 ) {
	modified.append( squares.substring( 0, column ) );
    }
    modified.append( val );
    if ( column < squares.length() - 1 ) {
	modified.append( squares.substring( column + 1, squares.length() ) );
    }

    layout[ row ] = modified;
    return layout;
}

int current_beach = 0;

void beach_completed(coords c)
{
    // We'll stop exploring any beach if it is out of twinkles
    current_beach = 0;

    // If we are exploring a single square, we're done.
    if (beach != 0) {
	completed = true;
	return;
    }
    // If we are spading multiple squares, move to next square
    if (mode == "spade") {
	spade_last_minutes = ( spade_last_minutes + 1 ) % 10000;
	return;
    }
}

buffer comb_square( coords c, string type )
{
    string cstring = c.to_url_string();
    print( "Combing the square at coordinates " + c + " which contains " + type );
    buffer page = visit_url( "choice.php?whichchoice=1388&option=4&coords=" + cstring );

    // Having combed this square, mark it in settings as combed.
    // This is now done by KoLmafia.
    // beach_layout layout = get_beach_layout().modify_square( c, "c" );
    // set_beach_layout( layout );

    return page;
}

buffer comb_beach( buffer page )
{
    void save_page_html( buffer page )
    {
	string filename = my_name() + "_beachcombings_" + now_to_string( "YYYYMMddHHmmssSSS" ) + ".txt";
	print( "Saving page HTML to " + filename, "red" );
	beachcombings[ count( beachcombings ) ] = filename;
	buffer_to_file( page, beach_file(filename) );
    }

    // We depend on KoLmafia to parse the page into properties
    int beach = get_minutes();
    beach_layout layout = get_beach_layout();
    sorted_beach_map map = sort_beach( beach, layout );

    // Inspect the layout and find all squares with twinkles.
    // (Or a whale)
    coords_list twinkles = extract_twinkles(map);

    // Save previously unvisited twinkles
    save_new_twinkles(twinkles);

    coords c = pick_coords_to_comb( beach, map );
    string type = code_to_type[ square_at( layout, c ) ];

    // Check if this was a special square
    boolean special = false;

    string tile_type = "unknown";

    // Look for beached whales
    if ( page.contains_text( "whale.png" ) ) {
	print( "You found a beached whale!", "red" );
	// Worth noting, but we also want to learn the hover text
	special = true;
	tile_type = "rare";
    }

    // Look for unknown square types
    if ( type == "?" ) {
	print( "You found an unknown square type!", "red" );
	// Worth noting, and we want to learn everything
	special = true;
    }

    if ( special ) {
	save_page_html( page );
	// For the above, log the page after combing, as well.
	// special = false;
    }

    page = comb_square( c, type );

    // Remove the newly combed tile from previously unknown twinkles
    int key = c.to_key();
    remove twinkle_tiles[key];
    remove twinkles[key];

    // We don't intentionally farm more than once in a beach segment
    // with no twinkles.
    if (count(twinkles) == 0) {
	beach_completed(c);
    }

    // Look for rainbow pearls
    if ( page.contains_text( "rainbow pearl" ) ) {
	print( "You found a rainbow pearl!", "red" );
	// Let's see the the result text
	special = true;
	tile_type = "rare";
    }

    // Look for meteorite fragments
    if ( page.contains_text( "meteorite fragment" ) ) {
	print( "You found a meteorite fragment!", "red" );
	// Let's see the the result text
	special = true;
	tile_type = "rare";
    }

    // Look for cursed pirate stuff
    if ( page.contains_text( "cursed pirate cutlass" ) ||
	 page.contains_text( "cursed tricorn hat" ) ||
	 page.contains_text( "cursed swash buckle" ) ) {
	print( "You found a cursed pirate hoard!", "red" );
	// Let's see the the result text
	special = true;
	tile_type = "rare";
    }

    // Look for messages in bottles
    if ( page.contains_text( "like it contains some sort of message" ) ) {
	print( "You found a message in a bottle!", "red" );
	// Let's see the the result text and learn how to parse out the message.
	special = true;
	tile_type = "rare";
    }

    if ( special ) {
	save_page_html( page );
    }

    int meat = page.extract_meat();
    int[item] items = page.extract_items();

    if (type != "combed sand" && tile_type == "unknown") {
	// Figure it out from the item drops
	tile_type = categorize_tile(items);
    }

    print( c + " is a" + (tile_type == "uncommon" ? "n" : "") + " '" + tile_type + "' tile.");

    save_visited_tile(c, tile_type);

    // Accumulate findings

    combed_rarities[ tile_type ]++;
    combed_types[ type ]++;
    combed_meat += meat;
    foreach it, count in items {
	combed_items[ it ] += count;
    }

    return page;
}

buffer comb_specific_beach( int beach )
{
    buffer page = run_choice( 1, "minutes=" + beach );
    current_beach = get_minutes();
    return comb_beach( page );
}

buffer comb_random_beach()
{
    // Wander to a random spot
    buffer page = run_choice( 2 );
    current_beach = get_minutes();
    return comb_beach( page );
}

buffer comb_next_beach()
{
    // Top level control for picking which beach to comb.
    // The comb has been used and the top-level choice is availabe.
    // We can either go to a RANDOM beach, or we can WANDER for a
    // specific number of minutes.

    // Based on "mode"
    //  "random"	Go to a new beach every time
    //  "rare"		Go to a beach with known rare tiles
    //  "spade"		Go next beach we are spading
    //  "beach"		Go to specified beach we are spading
    //
    // Based on "pick_strategy"
    //  "random"	Visit at most one twinkle
    //  "twinkle"	Visit all twinkles

    buffer page;
    switch (mode) {
    case "rare":
	// Until this is implemented, treat it as "random"
    case "random":
	// We'll go to random beachs, but will visit all twinkles
	if ( pick_strategy == "random" || current_beach == 0 ) {
	    page = comb_random_beach();
	} else {
	    page = comb_specific_beach( current_beach );
	}
	break;
    case "spade":
	if (spade_last_minutes < 0 || spade_last_minutes >= 10000) {
	    spade_last_minutes = 0;
	}
	page = comb_specific_beach( spade_last_minutes + 1 );
	break;
    case "beach":
	page = comb_specific_beach( beach );
	break;
    }

    return page;
}

int beach_comb_free( buffer page )
{
    int beaches_combed = 0;
    while ( !completed &&
	    ( page.contains_text( "free walks down the beach" ) ||
	      page.contains_text( "1 free walk down the beach" ) ) ) {
	page = comb_next_beach();
	beaches_combed++;
    }
    return beaches_combed;
}

int beach_comb_turns( buffer page, int turns )
{
    int beaches_combed = 0;
    while ( !completed && my_adventures() > 0 && turns-- > 0 ) {
	page = comb_next_beach();
	beaches_combed++;
    }
    return beaches_combed;
}

buffer pnum( buffer b, int n )
{
    buffer pnum_helper( buffer b, int n, int level )
    {
	if ( n >= 10 ) {
	    pnum_helper( b, n / 10, level + 1 );
	}
	b.append( to_string( n % 10 ) );
	if ( level > 0 && level % 3 == 0 ) {
	    b.append( "," );
	}
	return b;
    }

    if ( n < 0 ) {
	b.append( "-" );
	n = -n;
    }
    return pnum_helper( b, n, 0 );
}

string pnum( int n )
{
    buffer b;
    return pnum( b, n ).to_string();
}

// ***************************
//       Master Control      *
// ***************************

void beach_comb_free_only()
{
    buffer page = use_comb();
    int beaches_combed = beach_comb_free( page );
    put_away_comb();
    print( "Combed " + beaches_combed + " patches of beach using no turns." );
}

void beach_comb_turns_only( int turns )
{
    buffer page = use_comb();
    int beaches_combed = beach_comb_turns( page, turns );
    put_away_comb();
    print( "Combed " + beaches_combed + " patches of beach using turns." );

    // Save in a daily property
    int combed_previously = get_property( "_VBC.TurnsSpentCombing" ).to_int();
    int combed_today = combed_previously + beaches_combed;
    set_property( "_VBC.TurnsSpentCombing", combed_today );
}

void main(string... parameters )
{
    if ( available_amount( beach_comb ) == 0 &&
	 available_amount( driftwood_beach_comb ) == 0) {
        abort( "You don't have a Beach Comb or a driftwood beach comb!" );
    }

    // Parameters are optional. Depending on how the script is invoked,
    // there may be a single string with space-separated keywords, or
    // multiple strings. Whichever, turn into an array of keywords.
    string[] params = parameters.join_strings(" ").split_string(" ");

    // Parse parameters, if any. Do it before validating the
    // configuration, since parameters can override properties.
    parse_parameters(params);

    // Ensure configuration is sane
    validate_configuration();

    // Ensure the Beach Comb is either equippped or in inventory
    // The Beach Comb is not a quest item, so could be in closet, say.
    if ( available_amount( beach_comb ) > 0 &&
	 equipped_amount( beach_comb ) == 0 ) {
	retrieve_item( 1, beach_comb );
    }

    // driftwood beach comb is a "lasts until rollover" quest item.
    // That means that if you have one, it is either equipped or in inventory.
    // Therefore, do not need to retrieve it.

    print();
    if (!load_tile_data(true)) {
	abort("Unable to load tile data");
    }

    // Tile data is in multiple coords_list variables.
    // Create maps indexing it by # of minutes down the beach.
    print();
    populate_tile_maps(true);

    // If user only wants to see the data, nothing more to do
    if (mode == "data") {
	exit;
    }
  
    try {
	// Use all free combs
	beach_comb_free_only();

	// Optionally spend adventures for more combing
	if ( turns > 0 ) {
	    beach_comb_turns_only( turns );
	}
    } finally {
	print();
	print("Saving new tile data...");
	save_tile_data();

	print();
	foreach type in $strings[common, uncommon, rare, unknown] {
	    print( "Found " + combed_rarities[type] + " " + type + " tiles." );
	}

	print();
	foreach type, count in combed_types {
	    print( "Combed " + type + " " + count + " times." );
	}

	print();
	print( "Items combed:" );
	foreach it, count in combed_items {
	    print( it + " (" + count + ")" );
	}

	if ( combed_meat > 0 ) {
	    print();
	    print( "Meat combed:" + pnum( combed_meat ) );
	}

	if ( count( beachcombings ) > 0 ) {
	    print();
	    print( "Special beach combings saved:", "red" );
	    foreach n, filename in beachcombings {
		print( filename );
	    }
	}
    }
}