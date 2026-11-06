`ifndef AXI_TEST_SV
`define AXI_TEST_SV
class test_cfg;
  string       name;
  int unsigned seed;
  bit [3:0]    dir;        // 1 basic, 2 boundary, 4 strobe, 8 raw/waw
  int unsigned n_rand;
  int          cfg_aw, cfg_w, cfg_ar, cfg_b, cfg_r;   // -1 = random
  bit          mid_reset;  // idle DUT reset between directed and random phase
  bit          live_reset; // DUT reset while a read response is stalled

  function new(string n, int unsigned s, bit [3:0] d, int unsigned nr);
    name = n; seed = s; dir = d; n_rand = nr;
    cfg_aw = 0; cfg_w = 0; cfg_ar = 0; cfg_b = 0; cfg_r = 0;
    mid_reset = 1'b0;
    live_reset = 1'b0;
  endfunction
endclass

class test_lib;
  test_cfg     list [$];
  int unsigned base;

  function test_cfg add(string n, int unsigned off, bit [3:0] d, int unsigned nr);
    test_cfg c;
    c = new(n, base + off, d, nr);
    list.push_back(c);
    return c;
  endfunction

  function new(int unsigned base_seed);
    test_cfg c;
    base = base_seed;
    void'(add("t_directed", 0, 4'hF, 0));
    void'(add("t_boundary", 1, 4'h2, 0));
    void'(add("t_strobe",   2, 4'h4, 0));
    void'(add("t_rand",     3, 4'h0, 100));
    c = add("t_lat0",  4, 4'hF, 40);  c.cfg_b = 0;  c.cfg_r = 0;
    c = add("t_lat1",  5, 4'hF, 40);  c.cfg_b = 1;  c.cfg_r = 1;
    c = add("t_lat2",  6, 4'hF, 40);  c.cfg_b = 2;  c.cfg_r = 2;
    c = add("t_lat5",  7, 4'hF, 40);  c.cfg_b = 5;  c.cfg_r = 5;
    c = add("t_lat10", 8, 4'hF, 40);  c.cfg_b = 10; c.cfg_r = 10;
    c = add("t_lat_rand", 9, 4'hF, 40); c.cfg_b = -1; c.cfg_r = -1;
    c = add("t_reqdly", 10, 4'hF, 40); c.cfg_aw = 3; c.cfg_w = 5; c.cfg_ar = 2;
    c = add("t_reset",  11, 4'hF, 20); c.mid_reset = 1'b1;
    void'(add("t_rand_big", 12, 4'h0, 200));
    c = add("t_reset_live", 13, 4'hF, 20); c.live_reset = 1'b1;
  endfunction

  function test_cfg find(string n);
    foreach (list[i]) if (list[i].name == n) return list[i];
    return null;
  endfunction

  // missing goal name -> test that targets it
  function string gap_test(string g);
    case (g)
      "WR_LAT_D0",   "RD_LAT_D0":   return "t_lat0";
      "WR_LAT_D1",   "RD_LAT_D1":   return "t_lat1";
      "WR_LAT_D2",   "RD_LAT_D2":   return "t_lat2";
      "WR_LAT_D3_5", "RD_LAT_D3_5": return "t_lat5";
      "WR_LAT_D6_10","RD_LAT_D6_10":return "t_lat10";
      "RST_OBSERVED":               return "t_reset";
      default:                      return "t_rand_big";
    endcase
  endfunction
endclass
`endif