require 'rubygems'
require 'nokogiri'
require 'statemachine'
require 'yaml'

f = File.open("smalltestgraph.svg")
doc = Nokogiri::XML(f)
f.close

class Node
  attr_accessor :graphic_attrs, :shape, :label, :raph_string

  def parse_node(graphic)
    @graphic_attrs = {}
    graphic.each do |key,value|  
       @graphic_attrs[key] = value
    end
    
   # check that this is not a top level or definition node 
    if graphic.css('defs').empty? then
      @shape = Shape.new
      @label = Label.new
      graphic.children.each do |child|
        if child.node_name == 'text' && child[:x] != nil then
          @label.parse_label(child)
        elsif child[:x] != nil || child[:cx] != nil then
          @shape.parse_shape(child)     
        end
      end
    end 
  end
  
  def write_node
    @raph_string = ""
    
    if @shape != nil then @raph_string << @shape.write_shape end    
    if @label != nil then @raph_string << @label.write_label end    
    @raph_string
  end
end

class Shape
  attr_accessor :shape_name, :shape_attrs, :raph_string
  
  def parse_shape(shape)
    puts shape
    @shape_name = shape.name
    @shape_attrs = shape.attributes
  end
  
  def write_shape
    @raph_string = ""
    if @shape_name != nil then
      if @shape_name == 'ellipse' then @raph_string = self.write_ellipse end
      if @shape_name == 'rect' then @raph_string = self.write_rect end
    end
    @raph_string
  end
  
  def write_rect
    "rect(" + @shape_attrs['x'] + "," +  @shape_attrs['y'] + "," +  @shape_attrs['width'] + "," +  @shape_attrs['height'] + ")\n"
  end

  def write_ellipse
    "ellipse(" + @shape_attrs['cx'] + "," +  @shape_attrs['cy'] + "," +  @shape_attrs['rx'] + "," +  @shape_attrs['ry'] + ")\n"
  end
end


class Label
  attr_accessor :label_attrs, :label_name, :label_content, :raph_string
  
  def parse_label(label)
    puts label
    @label_name = label.name
    @label_attrs = label.attributes
    @label_content = label.content
  end
  
  def write_label
    if @label_content != nil && @label_attrs != nil then 
      @raph_string = "text(" + @label_attrs['x'] + "," + @label_attrs['y'] + ",\"" + @label_content + "\")"
      @raph_string
    else "" end
  end
end

class Edge
  attr_accessor :edge_attrs, :path, :fill, :raph_string

  def parse_edge(graphic)
    @edge_attrs = {}
    graphic.each do |key,value|  
      @edge_attrs[key] = value
    end
    
    # check that this is not a top level or definition node 
    if graphic.node_name == 'path' && graphic[:d] != nil then
       @path = graphic['d']
       @fill = graphic['fill']
    end
  end 
  
  def write_edge
    @raph_string = ""
    if @path != nil then @raph_string << "path(" + @path + ")" end    
    @raph_string
  end
end


# Search for nodes by css
Nodes = Array.new
doc.css('g').each do |graphic|
  this_node = Node.new
  this_node.parse_node(graphic)
  Nodes << this_node
end
# Now search for edges
Edges = Array.new
doc.css('path').each do |edge|
  this_edge = Edge.new
  this_edge.parse_edge(edge)
  Edges << this_edge
end

# Now write out new javascript
Nodes.each do |node|
   puts node.write_node  
end
Edges.each do |edge|
   puts edge.write_edge  
end

   # I adapted this code from SVGweb. They included this note:
   #          // NOTE: This code is very performance sensitive and was 
   #          // a bottleneck affecting page load; rewritten to not use
   #          // regular expressions as well as other tricks that were shown
   #          // to be faster (like caching data.length, parsing right into
   #          // an array instead of an intermediate string, etc.).
   #          // Be careful when changing this code without seeing what the
   #          // performance is before and after. See 
   #          // Issue 229 for details:
   #          // "Speedup page load time of MichaelN's static map page on IE"
   #          // http://code.google.com/p/svgweb/issues/detail?id=229
   # Actually all that remains of their trick is the character codes, so the 
   # performance is probably terrible. 

module ParsePath 
  class Command
    attr_reader :command, :arguments
    # a hash of the codes and corresponding names
    # I'm not actually using it right now, so it is commented out. 
    # commandnames = Hash["M","moveTo","L","lineTo","V","verticalLineTo","H","horizontalLineTo","A","ellipticalArc","C","cubicBezier","S","cubicBezierSmooth","Q","quadraticBezier","T","quadraticBezierSmooth","Z","closePath"]
    #this is a hash of the possible commands and expected number of arguments
    @@validcommands = Hash["M",2,"m",2,"L",2,"l",2,"V",1,"v",1,"H",1,"h",1,"A",6,"a",6,"S",6,"s",6,"Q",6,"q",6,"C",6,"c",6,"T",6,"t",6,"Z",2,"z",2]
    
    def initialize
      # this will be a letter command
      @command=nil
      # this will be an array of digits
      @partialnum=[]
      # this will be an array of numbers
      @arguments=[]
    end
    
    def add_command(command)
      if @@validcommands.keys.index(command) != nil then 
        # this is a valid command
        @command = command
      end
    end
    
    def add_digit(digit)
      @partialnum << digit
    end
    
    def finish_argument
      if @partialnum.length > 0 then 
        @arguments << @partialnum.join.to_i
        @partialnum=[]   #reset partial number
      end
   end

    def finish_command
      commandindex = @@validcommands.keys.index(@command)
      if commandindex != nil then 
        if @arguments.length == @@validcommands.values[commandindex] then
          # do nothing, we're happy
        elsif
          puts "wrong number of arguments for command"
        end
      end
    end
  end    


  class PathParsingContext
    attr_accessor :statemachine, :commands
    
    def initialize
      @commands = []
    end
  
    def startnewcommand(letter)
      @currentcommand = Command.new
      @currentcommand.add_command(letter)      
    end
    
    def addtonum(num)
      @currentcommand.add_digit(num)
    end
    
    def addnumtoargs
      @currentcommand.finish_argument
    end

    def finishcommand
      @currentcommand.finish_command
      @commands << @currentcommand
    end
  end
  
  def self.parsepath(pathstring) 
    # I'm making these helper functions to avoid
    # having to have nested if statements
    def handle_delimiter(machine)
      if machine.state == "buildingnumber" then 
        machine.endnumber
      end
    end

    def handle_newcommand(machine)
      if machine.state == "buildingnumber" then 
        machine.endnumber
        machine.endarguments
      elsif machine.state == "arguments" then 
        machine.endarguments    
      end
    end
    
    pathparsing = Statemachine.build do
      trans :command, :foundletter, :arguments, :startnewcommand
      trans :arguments, :foundnumber, :buildingnumber, :addtonum
      trans :buildingnumber, :foundnumber, :buildingnumber, :addtonum
      trans :buildingnumber, :endnumber, :arguments, :addnumtoargs
      trans :arguments, :endarguments, :command, :finishcommand
      context PathParsingContext.new 
    end
    @ppmachine = pathparsing.context.statemachine 
    
    pathstring.each_byte do |code|
      if (code >= 48 && code <= 57) || code == 45 || code == 101 || code == 46 then
      # 0 through 9, -, e-, or .
      @ppmachine.foundnumber code.chr
        
      elsif code == 44 || code == 32 || code == 10 || code == 13 then  
       # delimiter
        if @ppmachine.state == :buildingnumber then 
          @ppmachine.endnumber
        end

      elsif code >= 65 && code <= 122 then
        # A-Z and a-z
        puts code.chr
        if @ppmachine.state == :command then
          @ppmachine.foundletter code.chr
        elsif @ppmachine.state == :buildingnumber then 
          @ppmachine.endnumber
          @ppmachine.endarguments
          @ppmachine.foundletter code.chr
        elsif @ppmachine.state == :arguments then 
          @ppmachine.endarguments    
          @ppmachine.foundletter code.chr
        end

      else 
       # unknown character
      end  
    end
    
    #finalize result
    if @ppmachine.state == :buildingnumber then 
      @ppmachine.endnumber
      @ppmachine.endarguments
    elsif @ppmachine.state == :arguments then 
      @ppmachine.endarguments    
    end
    
    @ppmachine.context.commands
  end
  
  result = ParsePath.parsepath("M 20 20 L 10 10")
  result.each do |command| puts command.to_yaml end
end

                                                                              
