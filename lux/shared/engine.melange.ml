type renderer

let grid = 1024
let tile = 32
let tiles = grid / tile

let create_renderer : string -> int -> renderer =
  [%mel.raw
    {|function (id, n) {
  var canvas = document.getElementById(id);
  if (!canvas) return "no canvas #" + id;
  var gl = canvas.getContext("webgl2", { alpha: false, antialias: false, depth: false, stencil: false, powerPreference: "high-performance" });
  if (!gl) return "WebGL2 is not available";
  var common = `#version 300 es
precision highp float;
precision highp int;
const int N = ${n};
uniform float u_time;
uniform float u_now;
uniform sampler2D u_state;
uniform sampler2D u_style;
const float GAP = 0.06;
const float RAD = 0.16;
const vec3 BG = vec3(0.0012, 0.0013, 0.0020);
const vec3 DARK = vec3(0.0095, 0.0105, 0.0150);
const vec3 FLASH = vec3(1.0, 0.82, 0.55);
const float TAU = 6.2831853;
float tile_sd(vec2 uv) {
  vec2 q = abs(uv - 0.5) - vec2(0.5 - GAP - RAD);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - RAD;
}
vec3 glow(int s, vec2 uv) {
  vec2 p = uv - 0.5;
  float r = length(p) * 2.0;
  if (s == 0) return vec3(0.80, 0.34, 0.07) * pow(max(1.0 - r, 0.0), 1.4) + vec3(0.18, 0.12, 0.05) * exp(-r * r * 12.0);
  if (s == 1) {
    float cone = max(1.0 - abs(p.x) / (0.12 + 0.45 * uv.y), 0.0);
    return vec3(0.08, 0.22, 0.75) * exp(-uv.y * 1.6) * cone + vec3(0.07, 0.12, 0.21) * exp(-uv.y * uv.y * 30.0);
  }
  if (s == 2) {
    float d = length(uv - vec2(0.3, 0.7)) * 2.0;
    return vec3(0.22, 0.85, 0.10) * exp(-d * d * 1.4) * (0.7 + 0.3 * cos(d * 11.0));
  }
  if (s == 3) {
    float ring = exp(-pow((r - 0.62) / 0.17, 2.0));
    return vec3(0.55, 0.16, 0.92) * ring + vec3(0.12, 0.03, 0.22) * max(1.0 - r, 0.0);
  }
  float h = 1.0 - uv.y;
  return vec3(0.70, 0.08, 0.02) * exp(-h * 2.6) + vec3(0.25, 0.14, 0.02) * exp(-h * 10.0);
}
float hash(ivec2 c) {
  uint h = uint(c.x) * 1597334677u ^ uint(c.y) * 3812015801u;
  h ^= h >> 16;
  h *= 2246822519u;
  h ^= h >> 13;
  return float(h & 65535u) / 65535.0;
}
float level_of(vec4 s) { return floor(s.r * 255.0 + 0.5) + 256.0 * floor(s.g * 255.0 + 0.5); }
int style_of(vec4 s) { return int(s.b * 255.0 + 0.5); }
float breathe(float ph) { return 1.0 + 0.18 * sin(u_time * 0.8 + ph * TAU); }
float light(float level, float ph) {
  float flicker = 1.0 + 0.09 * sin(u_time * 7.1 + ph * TAU) + 0.06 * sin(u_time * 12.7 + ph * 19.0) + 0.04 * sin(u_time * 2.3 + ph * 41.0);
  return mix(0.35, 1.0, exp(-(level - 1.0) / 60.0)) * flicker;
}
float flash(float level) { return 0.5 * exp(-max(u_now - level, 0.0) * 1.8); }
vec3 card_mean(ivec2 c, vec4 s) {
  float ph = hash(c);
  float level = level_of(s);
  if (level == 0.0) {
    float cover = texelFetch(u_style, ivec2(0, 0), 0).a;
    return cover * DARK * breathe(ph) + (1.0 - cover) * BG;
  }
  vec4 g = texelFetch(u_style, ivec2(style_of(s), 0), 0);
  return g.a * (DARK + FLASH * flash(level)) + g.rgb * light(level, ph) + (1.0 - g.a) * BG;
}
vec3 card_detail(ivec2 c, vec2 uv, vec4 s, float aa) {
  float ph = hash(c);
  float m = 1.0 - smoothstep(-aa, aa, tile_sd(uv));
  float level = level_of(s);
  vec3 inner = level == 0.0 ? DARK * breathe(ph) : DARK + FLASH * flash(level) + glow(style_of(s), uv) * light(level, ph);
  return mix(BG, inner, m);
}
out vec4 o;
`;
  var styles = `
void main() {
  int s = int(gl_FragCoord.x);
  vec3 sum = vec3(0.0);
  float cover = 0.0;
  for (int j = 0; j < 64; j++) {
    for (int i = 0; i < 64; i++) {
      vec2 uv = (vec2(i, j) + 0.5) / 64.0;
      if (tile_sd(uv) < 0.0) { sum += glow(s, uv); cover += 1.0; }
    }
  }
  o = vec4(sum / 4096.0, cover / 4096.0);
}`;
  var means = `
void main() {
  ivec2 c = ivec2(gl_FragCoord.xy);
  o = vec4(card_mean(c, texelFetch(u_state, c, 0)), 1.0);
}`;
  var screen = `
uniform vec2 u_res;
uniform vec2 u_center;
uniform float u_ppc;
uniform float u_lod;
uniform sampler2D u_mean;
vec3 encode(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
void main() {
  vec2 frag = vec2(gl_FragCoord.x, u_res.y - gl_FragCoord.y);
  vec2 w = u_center + (frag - 0.5 * u_res) / u_ppc;
  vec2 cell = floor(w);
  ivec2 c = ivec2(cell);
  bool inside = c.x >= 0 && c.y >= 0 && c.x < N && c.y < N;
  vec4 s = inside ? texelFetch(u_state, c, 0) : vec4(0.0);
  float k = smoothstep(2.0, 8.0, u_ppc);
  vec3 col = vec3(0.0);
  if (k > 0.0) col = card_detail(c, w - cell, s, 0.75 / u_ppc);
  if (k < 1.0) {
    float cover = texelFetch(u_style, ivec2(0, 0), 0).a;
    vec3 far = inside ? textureLod(u_mean, w / float(N), u_lod).rgb : cover * DARK + (1.0 - cover) * BG;
    col = mix(far, col, k);
  }
  o = vec4(encode(col), 1.0);
}`;
  var vertex = `#version 300 es
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;
  var made = [];
  function compile(type, source) {
    var shader = gl.createShader(type);
    made.push(function () { gl.deleteShader(shader) });
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
    return shader;
  }
  function program(body) {
    var p = gl.createProgram();
    made.push(function () { gl.deleteProgram(p) });
    gl.attachShader(p, compile(gl.VERTEX_SHADER, vertex));
    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, common + body));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    gl.useProgram(p);
    var names = ["u_time", "u_now", "u_res", "u_center", "u_ppc", "u_lod"];
    var u = { program: p };
    for (var i = 0; i < names.length; i++) u[names[i]] = gl.getUniformLocation(p, names[i]);
    gl.uniform1i(gl.getUniformLocation(p, "u_state"), 0);
    gl.uniform1i(gl.getUniformLocation(p, "u_style"), 1);
    gl.uniform1i(gl.getUniformLocation(p, "u_mean"), 2);
    return u;
  }
  function texture(format, w, h, levels, min, mag) {
    var t = gl.createTexture();
    made.push(function () { gl.deleteTexture(t) });
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texStorage2D(gl.TEXTURE_2D, levels, format, w, h);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, min);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, mag);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  }
  function target(t) {
    var f = gl.createFramebuffer();
    made.push(function () { gl.deleteFramebuffer(f) });
    gl.bindFramebuffer(gl.FRAMEBUFFER, f);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) throw new Error("framebuffer incomplete");
    return f;
  }
  function free() { for (var i = made.length - 1; i >= 0; i--) made[i](); }
  try {
    var levels = Math.log2(n) + 1;
    var state = texture(gl.RGBA8, n, n, 1, gl.NEAREST, gl.NEAREST);
    var style = texture(gl.SRGB8_ALPHA8, 5, 1, 1, gl.NEAREST, gl.NEAREST);
    var mean = texture(gl.SRGB8_ALPHA8, n, n, levels, gl.LINEAR_MIPMAP_LINEAR, gl.LINEAR);
    var styleTarget = target(style);
    var meanTarget = target(mean);
    var stylePass = program(styles);
    var meanPass = program(means);
    var screenPass = program(screen);
    gl.bindVertexArray(gl.createVertexArray());
    gl.bindFramebuffer(gl.FRAMEBUFFER, styleTarget);
    gl.viewport(0, 0, 5, 1);
    gl.useProgram(stylePass.program);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, state);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, style);
    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, mean);
    var error = gl.getError();
    if (error !== gl.NO_ERROR) throw new Error("GL error " + error);
  } catch (e) {
    free();
    return "WebGL: " + e.message;
  }
  return { gl: gl, canvas: canvas, n: n, data: new Uint8Array(n * n * 4), meanTarget: meanTarget, meanPass: meanPass, screenPass: screenPass, free: free };
}|}]

let renderer_error : renderer -> string = [%mel.raw {|function (r) { return typeof r === "string" ? r : "" }|}]

let set_cell : renderer -> int -> int -> int -> unit =
  [%mel.raw
    {|function (r, cell, level, style) {
  var i = cell * 4;
  r.data[i] = level & 255;
  r.data[i + 1] = (level >> 8) & 255;
  r.data[i + 2] = style;
  r.data[i + 3] = 255;
}|}]

let upload : renderer -> int -> int -> int -> unit =
  [%mel.raw
    {|function (r, x, y, size) {
  var gl = r.gl;
  gl.activeTexture(gl.TEXTURE0);
  gl.pixelStorei(gl.UNPACK_ROW_LENGTH, r.n);
  gl.pixelStorei(gl.UNPACK_SKIP_PIXELS, x);
  gl.pixelStorei(gl.UNPACK_SKIP_ROWS, y);
  gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, size, size, gl.RGBA, gl.UNSIGNED_BYTE, r.data);
  gl.activeTexture(gl.TEXTURE2);
}|}]

let clear_cells : renderer -> unit = [%mel.raw {|function (r) { r.data.fill(0) }|}]

let resize : renderer -> int -> int -> unit =
  [%mel.raw
    {|function (r, w, h) {
  if (r.canvas.width !== w) r.canvas.width = w;
  if (r.canvas.height !== h) r.canvas.height = h;
}|}]

let draw : renderer -> float -> float -> float -> float -> float -> unit =
  [%mel.raw
    {|function (r, cx, cy, ppc, time, now) {
  var gl = r.gl, n = r.n, w = r.canvas.width, h = r.canvas.height, lod = Math.log2(1 / ppc);
  if (ppc < 8) {
    var m = 8 / ppc + 2;
    var x0 = Math.max(0, Math.floor(cx - w / 2 / ppc - m)), x1 = Math.min(n, Math.ceil(cx + w / 2 / ppc + m));
    var y0 = Math.max(0, Math.floor(cy - h / 2 / ppc - m)), y1 = Math.min(n, Math.ceil(cy + h / 2 / ppc + m));
    if (x1 > x0 && y1 > y0) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, r.meanTarget);
      gl.viewport(0, 0, n, n);
      gl.enable(gl.SCISSOR_TEST);
      gl.scissor(x0, y0, x1 - x0, y1 - y0);
      gl.useProgram(r.meanPass.program);
      gl.uniform1f(r.meanPass.u_time, time);
      gl.uniform1f(r.meanPass.u_now, now);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.disable(gl.SCISSOR_TEST);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      if (lod > 0) gl.generateMipmap(gl.TEXTURE_2D);
    }
  }
  var s = r.screenPass;
  gl.viewport(0, 0, w, h);
  gl.useProgram(s.program);
  gl.uniform1f(s.u_time, time);
  gl.uniform1f(s.u_now, now);
  gl.uniform2f(s.u_res, w, h);
  gl.uniform2f(s.u_center, cx, cy);
  gl.uniform1f(s.u_ppc, ppc);
  gl.uniform1f(s.u_lod, lod);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}|}]

let dispose : renderer -> unit =
  [%mel.raw
    {|function (r) {
  r.free();
  var lose = r.gl.getExtension("WEBGL_lose_context");
  if (lose) lose.loseContext();
}|}]

let pixel_ratio : unit -> float = [%mel.raw {|function () { return window.devicePixelRatio || 1 }|}]

type t = {
  r : renderer;
  run : Run.t;
  mutable input : Input.t option;
  dirty : Bytes.t;
  dirty_list : int array;
  mutable dirty_len : int;
  mutable stopped : bool;
}

let following t = Run.following t.run
let readout t = Run.readout t.run
let follow t = Run.follow t.run

let measure t =
  let dpr = Float.min 2. (pixel_ratio ()) in
  Run.resize t.run ~width:(Input.width ()) ~height:(Input.height ());
  resize t.r
    (int_of_float (Float.round (Run.width t.run *. dpr)))
    (int_of_float (Float.round (Run.height t.run *. dpr)));
  dpr

let take_fresh t =
  let spread = Run.spread t.run in
  let size = Spread.size spread and level = Spread.level spread in
  for i = 0 to Spread.fresh_count spread - 1 do
    let cell = Spread.fresh spread i in
    set_cell t.r cell level (Option.value (Spread.style spread cell) ~default:0);
    let index = (cell / size / tile * tiles) + (cell mod size / tile) in
    if Bytes.get_uint8 t.dirty index = 0 then begin
      Bytes.set_uint8 t.dirty index 1;
      t.dirty_list.(t.dirty_len) <- index;
      t.dirty_len <- t.dirty_len + 1
    end
  done;
  for i = 0 to t.dirty_len - 1 do
    let index = t.dirty_list.(i) in
    Bytes.set_uint8 t.dirty index 0;
    upload t.r (index mod tiles * tile) (index / tiles * tile) tile
  done;
  t.dirty_len <- 0

let reload t =
  clear_cells t.r;
  upload t.r 0 0 grid;
  take_fresh t

let start ~canvas_id =
  let r = create_renderer canvas_id grid in
  match renderer_error r with
  | "" ->
      let run = Run.create ~size:grid ~seed:(Input.random_seed ()) ~width:(Input.width ()) ~height:(Input.height ()) in
      let t =
        {
          r;
          run;
          input = None;
          dirty = Bytes.make (tiles * tiles) '\000';
          dirty_list = Array.make (tiles * tiles) 0;
          dirty_len = 0;
          stopped = false;
        }
      in
      reload t;
      t.input <- Input.attach canvas_id run;
      Ok t
  | message -> Error message

let frame t now =
  if not t.stopped then begin
    let dpr = measure t in
    if Run.tick t.run now then take_fresh t;
    draw t.r (Run.center_x t.run) (Run.center_y t.run) (Run.scale t.run *. dpr) (Run.seconds t.run) (Run.glow_level t.run)
  end

let restart t =
  Run.restart t.run ~seed:(Input.random_seed ());
  reload t

let stop t =
  if not t.stopped then begin
    t.stopped <- true;
    Option.iter Input.detach t.input;
    t.input <- None;
    dispose t.r
  end
