#encoding: UTF-8
require 'gosu'
require 'matrix'
require 'date'

class Minesweeper < Gosu::Window
  attr_accessor :rows, :cols
  TILE_COLOR = Gosu::Color::GRAY
  TILE_ACCENT_LT = Gosu::Color.argb(0xffdcdcdc)
  TILE_ACCENT_DK = Gosu::Color.new(0xff666666)
  TILE_SIZE = 40
  PADDING = 2
  BORDER = 4
  BLOCK_SIZE = TILE_SIZE - PADDING*2 - BORDER*2
  STATUS_SIZE = TILE_SIZE * 3

  EMPTY = 1
  MINE = 2
  REVEALED = 4
  FLAGGED = 8
  EXPLODED = 16

  FLAG_ICON = Gosu::Image.new("./flag.png")
  BOMB_ICON = Gosu::Image.new("./bomb.png")

  STARTING = 0
  PLAYING = 1
  WON = 2
  LOST = 3

  NUMBER_COLOR = {
    1 => Gosu::Color.argb(0xff0000ff),
    2 => Gosu::Color.argb(0xff008200),
    3 => Gosu::Color.argb(0xfffe0000),
    4 => Gosu::Color.argb(0xff000084),
    5 => Gosu::Color.argb(0xff840000),
    6 => Gosu::Color.argb(0xff008284),
    7 => Gosu::Color.argb(0xff840084),
    8 => Gosu::Color.argb(0xff333333)
  }

  def initialize
    @font_size = 25
    @text_spacing = TILE_SIZE
    @text_offset = 1
    if ARGV.length <= 1
      difficulty = ARGV[0] || "easy"
      if difficulty == "hard"
        @rows = 16
        @cols = 40
        @mine_count = 99
      elsif difficulty == "medium"
        @rows = 16
        @cols = 16
        @mine_count = 40
      else
        @rows = 10
        @cols = 10
        @mine_count = 10
        @font_size = 16
        @text_spacing = 16
        @text_offset = 3
      end
    elsif ARGV.length == 3
      @rows = ARGV[0].to_i
      @cols = ARGV[1].to_i
      @mine_count = ARGV[2].to_i
      if @cols < 16
        @font_size = 16
        @text_spacing = 16
        @text_offset = 3
      end
    end

    load_scores

    @font = Gosu::Font.new(@font_size, bold: true)
    @small_font = Gosu::Font.new((@font_size * 0.75).to_i)
    super TILE_SIZE * @cols, TILE_SIZE * @rows + STATUS_SIZE
    self.resizable = true
    self.caption = "Minesweeper"
    reset_game
  end

  def save_scores
    @scores = @scores.sort_by do |score|
      [-score[:mines], score[:time]]
    end.take(13)
    save_file = File.join(Dir.home, ".rbminesweeper")
    File.open(save_file, "w") do |f|
      f.puts "mines,time,date,rows,cols"
      @scores.each do |score|
        f.puts "#{score[:mines]},#{score[:time]},#{score[:date].to_i},#{score[:rows]},#{score[:cols]}"
      end
    end
  end

  def load_scores
    @scores = []
    save_file = File.join(Dir.home, ".rbminesweeper")
    File.open(save_file, "r") do |f|
      f.readline # Read and skip header
      while !f.eof?
        mines, time, date, rows, cols = f.readline.split(",")
        @scores << {mines: mines.to_i, time: time.to_i, date: Time.at(date.to_i), rows: rows.to_i, cols: cols.to_i}
      end
    end
  rescue Errno::ENOENT
    # do nothing, it's ok ...
  end

  def reset_game
    @grid = Matrix.build(@rows, @cols) { |r,c| EMPTY }
    @minecount = Matrix.build(@rows, @cols) { |r,c| 0 }
    @status = STARTING
  end

  def start_game
    @status = PLAYING
    @mine_count.times do
      loop do
        r = rand(@rows)
        c = rand(@cols)
        if !has_flag(r, c, MINE)
          set_flag(r, c, MINE)
          break
        end
      end
    end
    @minecount = Matrix.build(@rows, @cols) { |r,c| count_mines_near(r,c) }
    @first_move = true
    @flag_count = 0
    @start_time = Time.now.to_i
    @end_time = nil
  end

  def set_flag(r, c, flag)
    @grid[r, c] |= flag
  end

  def remove_flag(r, c, flag)
    if has_flag(r, c, flag)
      toggle_flag(r, c, flag)
    end
  end

  def has_flag(r, c, flag)
    @grid[r, c] & flag > 0
  end

  def toggle_flag(r, c, flag)
    @grid[r, c] ^= flag
  end

  def update
    return if @status == WON
    # check for victory
    count = 0
    for r in (0...@rows)
      for c in (0...@cols)
        if has_flag(r, c, (REVEALED | FLAGGED))
          count += 1
        end
      end
    end
    if @flag_count == @mine_count && count == (@rows * @cols) && @status != LOST
      @status = WON
      @end_time = Time.now.to_i
      @scores << {mines: @mine_count, time: @end_time - @start_time, date: Time.now, rows: @rows, cols: @cols}
      save_scores
      reveal_board
    end
  end

  def move_mine(r, c)
    toggle_flag(r, c, MINE)
    loop do
      nr = rand(@rows)
      nc = rand(@cols)
      if !has_flag(nr, nc, MINE)
        set_flag(nr, nc, MINE)
        break
      end
    end
  end

  def reveal_board
    for r in (0...@rows)
      for c in (0...@cols)
        set_flag(r, c, REVEALED)
        remove_flag(r, c, FLAGGED)
      end
    end
  end

  def extended_reveal(r0, c0)
    stack = []
    add_neighbors = lambda do |r, c|
      rmin = r == 0 ? 0 : r - 1
      rmax = r >= (@rows-1) ? r : r + 1
      cmin = c == 0 ? 0 : c - 1
      cmax = c >= (@cols-1) ? c : c + 1
      (rmin..rmax).each do |check_row|
        (cmin..cmax).each do |check_col|
          if !(check_row == r && check_col == c)
            stack << [check_row, check_col]
          end
        end
      end
    end
    add_neighbors.call(r0, c0)
    while !stack.empty?
      node = stack.shift
      if !has_flag(node.first, node.last, REVEALED)
        set_flag(node.first, node.last, REVEALED)
        if @minecount[node.first, node.last] == 0
          add_neighbors.call(node.first, node.last)
        end
      end
    end
  end

  def button_up(id)
    case id
    when Gosu::KB_SPACE
      if [WON, LOST].include?(@status)
        reset_game
      elsif @status == STARTING
        start_game
      end
    when Gosu::KB_Q
      self.close!
    when Gosu::MS_RIGHT
      return if @status != PLAYING
      c = self.mouse_x.to_i / TILE_SIZE
      r = self.mouse_y.to_i / TILE_SIZE
      if c < @cols && r < @rows
        if !has_flag(r, c, REVEALED)
          if !has_flag(r, c, FLAGGED)
            @flag_count += 1
          else
            @flag_count -= 1
          end
          toggle_flag(r, c, FLAGGED)
        end
        @first_move = false
      end
    when Gosu::MS_LEFT
      return if @status != PLAYING
      c = self.mouse_x.to_i / TILE_SIZE
      r = self.mouse_y.to_i / TILE_SIZE
      if c < @cols && r < @rows
        if has_flag(r, c, MINE)
          if @first_move
            move_mine(r, c)
          else
            set_flag(r, c, EXPLODED)
            @status = LOST
            @end_time = Time.now.to_i
            reveal_board
          end
        end
        if !has_flag(r, c, REVEALED)
          set_flag(r, c, REVEALED)
          remove_flag(r, c, FLAGGED)
          if @minecount[r,c] == 0
            extended_reveal(r,c)
          end
        end
        @first_move = false
      end
    end
  end
  
  def draw
    if @status == STARTING
      draw_starting
    else
      @rows.times do |r|
        @cols.times do |c|
          draw_block(r, c)
        end
      end
    end
    draw_status
  end

  def elapsed_time(start_time, end_time, elapsed = nil)
    elapsed ||= (end_time || Time.now.to_i) - start_time
    sec = elapsed % 60
    minutes = elapsed / 60
    sprintf("%02dm %02ds", minutes, sec)
  end

  def draw_starting
    draw_rect(TILE_SIZE - BORDER, TILE_SIZE - BORDER,
        (@cols - 2) * TILE_SIZE + BORDER*2, (@rows - 2) * TILE_SIZE + BORDER*2,
        Gosu::Color::CYAN, 1)
    draw_rect(TILE_SIZE, TILE_SIZE, (@cols - 2) * TILE_SIZE, (@rows - 2) * TILE_SIZE,
        Gosu::Color::BLACK, 1)
    draw_rect(TILE_SIZE, 2 * TILE_SIZE - BORDER, (@cols - 2) * TILE_SIZE, BORDER,
        Gosu::Color::CYAN, 1)
    @font.draw_text_rel("Leader Board",
      @cols * TILE_SIZE / 2, TILE_SIZE, 3,
      0.5, 0, 1.0, 1.0, Gosu::Color::WHITE)
    msg = []
    @scores.take(13).each do |score|
      str = "<c=e0d179>#{score[:date].strftime("%Y-%m-%d %H:%M")}</c>"
      str << " <c=840000>#{elapsed_time(nil, nil, score[:time])}</c>"
      str << " <c=008284>Mines: #{score[:mines]}</c>"
      str << " <c=840084>Size: #{score[:rows]}x#{score[:cols]}</c>"
      msg << str
    end
    msg.each_with_index do |str, idx|
      @small_font.draw_markup(str,
        @cols + TILE_SIZE + BORDER, TILE_SIZE + (@text_offset + idx) * @text_spacing + BORDER, 3,
        1.0, 1.0, Gosu::Color::WHITE)
    end
  end

  def draw_status
    msg = []
    case @status
    when PLAYING
      msg << "#{@flag_count}/#{@mine_count} mines found"
      msg << elapsed_time(@start_time, @end_time)
    when WON
      msg << "YOU WON \u{1F60A}\u{1F60A}\u{1F60A} in #{elapsed_time(@start_time, @end_time)}"
      msg << "Press Space to continue"
      msg << "Press Q to quit"
    when LOST
      msg << "YOU LOST \u{1F635}\u{1F635}\u{1F635}"
      msg << "Press Space to continue"
      msg << "Press Q to quit"
    when STARTING
      msg << "Press Space start a new game"
      msg << "Press Q to quit"
    end
    msg.each_with_index do |str, idx|
      @font.draw_text_rel(str,
        @cols * TILE_SIZE / 2, (@rows + idx) * TILE_SIZE, 3,
        0.5, 0, 1.0, 1.0, Gosu::Color::WHITE)
    end
  end

  def count_mines_near(r, c)
    rmin = r == 0 ? 0 : r - 1
    rmax = r >= (@rows-1) ? r : r + 1
    cmin = c == 0 ? 0 : c - 1
    cmax = c >= (@cols-1) ? c : c + 1
    num = 0
    (rmin..rmax).each do |check_row|
      (cmin..cmax).each do |check_col|
        if check_row == r && check_col == c
          next
        end
        if has_flag(check_row, check_col, MINE)
          num += 1
        end
      end
    end
    num
  end

  def draw_block(r, c)
    if has_flag(r, c, REVEALED)
      color = has_flag(r, c, EXPLODED) ? Gosu::Color::RED : Gosu::Color::WHITE
      # center
      draw_rect(c * TILE_SIZE + PADDING, r * TILE_SIZE + PADDING,
              BLOCK_SIZE + BORDER*2, BLOCK_SIZE + BORDER*2,
              color, 1)
      if !has_flag(r, c, MINE) && (mc = @minecount[r, c]) > 0
        @font.draw_text_rel("#{mc}", c * TILE_SIZE + TILE_SIZE/2, r * TILE_SIZE + TILE_SIZE / 2, 2,
                            0.5, 0.5, 1.0, 1.0, NUMBER_COLOR[mc] || Gosu::Color::BLACK)
      end
    else
      # center
      draw_rect(c * TILE_SIZE + PADDING + BORDER, r * TILE_SIZE + PADDING + BORDER,
                BLOCK_SIZE, BLOCK_SIZE,
                TILE_COLOR, 1)
      # top border
      draw_rect(c * TILE_SIZE + PADDING, r * TILE_SIZE + PADDING,
                TILE_SIZE - PADDING * 2 - BORDER, BORDER,
                TILE_ACCENT_LT, 1)
      draw_triangle(c * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE, r * TILE_SIZE + PADDING, TILE_ACCENT_LT,
                    c * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE + BORDER, r * TILE_SIZE + PADDING, TILE_ACCENT_LT,
                    c * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE, r * TILE_SIZE + PADDING + BORDER, TILE_ACCENT_LT, 1)
      # left border
      draw_rect(c * TILE_SIZE + PADDING, r * TILE_SIZE + PADDING + BORDER,
                BORDER, BLOCK_SIZE,
                TILE_ACCENT_LT, 1)
      draw_triangle(c * TILE_SIZE + PADDING, r * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE, TILE_ACCENT_LT,
                    c * TILE_SIZE + PADDING + BORDER, r * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE, TILE_ACCENT_LT,
                    c * TILE_SIZE + PADDING, r * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE + BORDER, TILE_ACCENT_LT, 1)
      # bottom border
      draw_rect(c * TILE_SIZE + PADDING + BORDER, r * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE,
                BLOCK_SIZE + BORDER, BORDER,
                TILE_ACCENT_DK, 1)
      draw_triangle(c * TILE_SIZE + PADDING + BORDER, r * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE, TILE_ACCENT_DK,
                    c * TILE_SIZE + PADDING + BORDER, r * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE + BORDER, TILE_ACCENT_DK,
                    c * TILE_SIZE + PADDING, r * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE + BORDER, TILE_ACCENT_DK, 1)
      # right border
      draw_rect(c * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE, r * TILE_SIZE + PADDING + BORDER,
                BORDER, BLOCK_SIZE,
                TILE_ACCENT_DK, 1)
      draw_triangle(c * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE, r * TILE_SIZE + PADDING + BORDER, TILE_ACCENT_DK,
                    c * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE + BORDER, r * TILE_SIZE + PADDING + BORDER, TILE_ACCENT_DK,
                    c * TILE_SIZE + PADDING + BORDER + BLOCK_SIZE + BORDER, r * TILE_SIZE + PADDING, TILE_ACCENT_DK, 1)
    end
    if has_flag(r, c, FLAGGED)
      FLAG_ICON.draw(c * TILE_SIZE + PADDING + BORDER, r * TILE_SIZE + PADDING + BORDER, 1)
    end
    if has_flag(r, c, REVEALED) && has_flag(r, c, MINE)
      BOMB_ICON.draw(c * TILE_SIZE + PADDING + BORDER, r * TILE_SIZE + PADDING + BORDER, 1)
    end
  end
end

Minesweeper.new.show
