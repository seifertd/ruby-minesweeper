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
  FONT_SIZE = 35
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
    @scores = []
    @rows = 16 
    @cols = 16
    @font = Gosu::Font.new(FONT_SIZE, bold: true)
    super TILE_SIZE * @cols, TILE_SIZE * @rows + STATUS_SIZE
    self.resizable = true
    self.caption = "Minesweeper"
    reset_game
  end

  def reset_game
    @grid = Matrix.build(@rows, @cols) { |r,c| EMPTY }
    @mine_count = 40
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
    if @flag_count == @mine_count && count == (@rows * @cols)
      @status = WON
      @end_time = Time.now.to_i
      @scores << {mines: @mine_count, time: @end_time - @start_time, date: Time.now, rows: @rows, cols: @cols}
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
      end
    when Gosu::KB_Q
      if [WON, LOST].include?(@status)
        self.close!
      end
    when Gosu::MS_RIGHT
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
    @rows.times do |r|
      @cols.times do |c|
        draw_block(r, c)
      end
    end
    draw_status
  end

  def elapsed_time
    elapsed = (@end_time || Time.now.to_i) - @start_time
    sec = elapsed % 60
    minutes = elapsed / 60
    sprintf("%02dm %02ds", minutes, sec)
  end

  def draw_status
    case @status
    when PLAYING
      msg = ["#{@flag_count}/#{@mine_count} mines found"]
      msg << elapsed_time
    when WON
      msg = ["YOU WON \u{1F60A}\u{1F60A}\u{1F60A} in #{elapsed_time}",
             "Press Space to start again",
             "Press Q to quit"]
    when LOST
      msg = ["YOU LOST \u{1F635}\u{1F635}\u{1F635}",
             "Press Space to start again",
             "Press Q to quit"]
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
