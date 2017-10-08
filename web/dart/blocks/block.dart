/*
 * NetTango
 * Copyright (c) 2017 Michael S. Horn, Uri Wilensky, and Corey Brady
 * 
 * Northwestern University
 * 2120 Campus Drive
 * Evanston, IL 60613
 * http://tidal.northwestern.edu
 * http://ccl.northwestern.edu
 
 * This project was funded in part by the National Science Foundation.
 * Any opinions, findings and conclusions or recommendations expressed in this
 * material are those of the author(s) and do not necessarily reflect the views
 * of the National Science Foundation (NSF).
 */
part of NetTango;

const BLOCK_WIDTH = 80.0; // 58
const BLOCK_HEIGHT = 34.0; //50.0;
const BLOCK_PADDING = 10.0;
const BLOCK_INDENT = 25.0;  /// left side connector area for blocks
const BLOCK_GUTTER = 10.0;


/**
 * Visual programming block
 */
class Block implements Touchable {
  
  /// Used to generate unique block id numbers
  static int _BLOCK_ID = 0;

  /// unique internal block ID number
  int id;
  
  /// text displayed inside the block
  String name;
  
  /// internal action name (usually the same as text)
  String action;

  /// language specific command type used by code formatters (e.g. nlogo:command)
  var type;

  /// formatting hint to help translate the parse tree into source code.
  /// parameters can be referenced using python format syntax. e.g. 
  /// "if random 100 > {0}"
  String format;

  /// block dimensions and position
  num x = 0.0, y = 0.0, width = 0.0, height = 0.0;

  /// next block in the chain (below)
  Block next;
  
  /// previous block in the chain (above)
  Block prev;

  /// current indentation level
  int indent = 0;

  /// the most immediate containing control block (or null)
  ControlBlock parent;

  /// parameters for this block (optional)
  List<Parameter> params = new List<Parameter>();

  /// CSS color of the block
  String blockColor = '#6b9bc3'; //'#d2584a';

  /// CSS color of the text
  String textColor = 'white';

  /// CSS border color of the block
  String borderColor = "rgba(255, 255, 255, 0.8)";

  /// CSS font spec
  String font = "400 14px 'Poppins', sans-serif";

  /// link back to the main workspace
  CodeWorkspace workspace;

  /// allow connections above this block?
  bool hasTopConnector = true;

  /// is the block being dragged 
  bool _dragging = false;
  
  /// used for dragging the block on the screen
  num _touchX, _touchY, _lastX, _lastY;

  /// is the block really just a menu item?
  bool _inMenu = false;

  /// was this block just dragged from the menu for the first time? 
  bool _wasInMenu = true;

  /// indentation delta above this block
  int get indentAbove => 0;

  /// indentation delta below this block
  int get indentBelow => 0;

  bool get hasParams => params.isNotEmpty;

  bool get hasNext => next != null;
  
  bool get hasPrev => prev != null;

  num get topConnectorY => y;
  
  num get bottomConnectorY => y + height;

  bool get dragging => _dragging ? true : hasPrev ? prev.dragging : false;

  Block get bottomOfChain => hasNext ? next.bottomOfChain : this;

  Block get nextChain => hasNext ? next : (parent != null) ? parent.nextClause : null;

  bool get isStartOfChain => !hasPrev;


  Block(this.workspace, this.action) {
    id = Block._BLOCK_ID++;
    width = BLOCK_WIDTH;
    height = BLOCK_HEIGHT;
    name = action;
  }


  /// create a block from a JSON definition
  factory Block.fromJSON(CodeWorkspace workspace, Map json) {

    Block block;
    String action = toStr(json["action"]);  // required - must be unique
    String name = toStr(json["name"], action);

    //----------------------------------------------------------
    // block types
    //----------------------------------------------------------
    if (json["clauses"] is List) {
      block = new BeginBlock(workspace, action);
    }
    else if (json["type"] == "clause") {
      block = new ClauseBlock(workspace, action);
    }
    else {
      block = new Block(workspace, action);
    }

    //----------------------------------------------------------
    // block properties
    //----------------------------------------------------------
    block.name = name;
    block.type = toStr(json["type"]);
    block.format = toStr(json["format"], null);
    block.blockColor = toStr(json["blockColor"], block.blockColor);
    block.textColor = toStr(json["textColor"], block.textColor);
    block.font = toStr(json["font"], block.font);
    block.hasTopConnector = ! toBool(json["start"], false);

    //----------------------------------------------------------
    // parameters
    //----------------------------------------------------------
    if (json["params"] is List) {
      for (var p in json["params"]) {
        Parameter param = new Parameter.fromJSON(block, p);
        if (param != null) block.params.add(param);
      }
    }


    //----------------------------------------------------------
    // clauses
    //----------------------------------------------------------
    if (block is BeginBlock && json["clauses"] is List) {
      for (var c in json["clauses"]) {
        c["type"] = "clause";
        ClauseBlock clause = new Block.fromJSON(workspace, c) as ClauseBlock;
        (block as BeginBlock)._addClause(clause);
      }
    }

    return block;
  }


  Block clone() {
    Block other = new Block(workspace, action);
    _copyTo(other);
    return other;
  }


  void _copyTo(Block other) {
    other.name = name;
    other.type = type;
    other.format = format;
    other.blockColor = blockColor;
    other.textColor = textColor;
    other.font = font;
    other.width = width;
    other.height = height;
    other.hasTopConnector = hasTopConnector;
    for (Parameter param in params) {
      other.params.add(param.clone(other));
    }
  }


//-------------------------------------------------------------------------
/// export block to a JSON object
//-------------------------------------------------------------------------
  Map toJSON() {
    var data = { };
    data["id"] = id;
    data["name"] = name;
    data["action"] = action;
    data["type"] = type;
    data["format"] = format;
    data["start"] = hasTopConnector;
    if (params.isNotEmpty) {
      data["params"] = [];
      for (Parameter param in params) {
        data["params"].add(param.toJSON());
      }
    }
    return data;
  }


//-------------------------------------------------------------------------
/// export this chain of blocks 
//-------------------------------------------------------------------------
  List exportParseTree() {
    List chain = [];
    _exportParseTree(chain);
    return chain;
  }

  void _exportParseTree(List chain) {
    chain.add(toJSON());
    if (next != null) next._exportParseTree(chain);
  }


//-------------------------------------------------------------------------
/// resize a chain of blocks.
//-------------------------------------------------------------------------
  num _resizeChain(CanvasRenderingContext2D ctx, num maxX) {

    width = max(BLOCK_WIDTH, _getNaturalWidth(ctx));

    /// resize all of the parameters
    num pwidth = 0;
    if (!_inMenu && hasParams) {
      for (Parameter param in params) {
        param._resize(ctx);
        pwidth += param.width + BLOCK_PADDING;
      }
    }
    maxX = max(maxX, x + width + pwidth);
    Block below = nextChain;
    if (below != null) {
      maxX = below._resizeChain(ctx, maxX);
    }

    width = maxX - x;
    return maxX;
  }


//-------------------------------------------------------------------------
/// recompute block indentation 
//-------------------------------------------------------------------------
  void _reindentChain(int indent, ControlBlock parent) {
    this.indent = indent;
    this.parent = parent;
    if (hasNext) next._reindentChain(indent + indentBelow, parent);
  }


//-------------------------------------------------------------------------
/// reposition and resize a chain of blocks.
//-------------------------------------------------------------------------
  void _repositionChain() {
    if (next != null) {
      next.y = y + height;
      next.x = x + (next.indent - indent) * BLOCK_INDENT;
      next._repositionChain();
    }
  }


  /// move a single block to a location
  void moveBlock(num x, num y) {
    this.x = x;
    this.y = y;
  }


  /// attach to the bottom of other
  void _snapBelow(Block other) {
    Block below = other.next;
    other.next = this;
    this.prev = other;

    if (below != null) {
      Block bottom = bottomOfChain;
      below.prev = bottom;
      bottom.next = below;
    }
  }


  /// attach to the top of other
  void _snapAbove(Block other) {
    other.prev = this;
    this.next = other;
  }


  num _getTextWidth(CanvasRenderingContext2D ctx) {
    num w = 0;
    ctx.save();
    {
      ctx.font = font;
      w = ctx.measureText(name).width;
    }
    ctx.restore();
    return w;
  }  


  num _getNaturalWidth(CanvasRenderingContext2D ctx) {
    return _getTextWidth(ctx) + BLOCK_PADDING * 2;
  }


  bool animate() {
    if (_dragging) {
      x += _touchX - _lastX;
      y += _touchY - _lastY;
      _lastX = _touchX;
      _lastY = _touchY;
    }
    return _dragging;
  }


//=================================================================  
// WARNING: EXTREMELY MESSY DRAWING CODE BELOW THIS POINT.
// TRIED TO MAKE IT AS NEAT AS POSSIBLE
//=================================================================  

  void _drawLabel(CanvasRenderingContext2D ctx) {
    ctx.save();
    {
      ctx.fillStyle = textColor;
      ctx.font = font;
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(name, x + BLOCK_PADDING, y + height / 2);
    }
    ctx.restore();
  }


  void _drawOutline(CanvasRenderingContext2D ctx) {
    ctx.save();
    {
      _outlineBlock(ctx);
      ctx.strokeStyle = borderColor;
      ctx.lineWidth = 1.5;
      ctx.lineJoin = "round";
      ctx.stroke();
    }
    ctx.restore();
  }


  void _drawBlock(CanvasRenderingContext2D ctx) {
    ctx.save();
    {
      _outlineBlock(ctx);
      ctx.fillStyle = blockColor;
      ctx.fill();
      ctx.fillStyle = "rgba(0, 0, 0, ${min(1, 0.075 * indent)}";
      ctx.fill();
    }
    ctx.restore();
  }


  void _drawTopConnector(CanvasRenderingContext2D ctx) {
    ctx.save();
    {
      ctx.lineWidth = 5;
      ctx.strokeStyle = borderColor;
      ctx.beginPath();
      ctx.moveTo(x + BLOCK_PADDING + BLOCK_INDENT * indentAbove, y);
      _outlineTop(ctx, !hasPrev && hasTopConnector);
      ctx.stroke();
    }
    ctx.restore();
  }


  void _drawBottomConnector(CanvasRenderingContext2D ctx) {
    ctx.save();
    {
      ctx.lineWidth = 5;
      ctx.strokeStyle = borderColor;
      ctx.beginPath();
      ctx.moveTo(x + width - BLOCK_PADDING, y + height);
      _outlineBottom(ctx, !hasNext && indent == 0);
      ctx.stroke();
    }
    ctx.restore();
  }


  void _drawParameters(CanvasRenderingContext2D ctx) {
    num left = width;
    for (int i=params.length - 1; i >= 0; i--) {
      left -= (BLOCK_PADDING + params[i].width);
      params[i].draw(ctx, left);
    }
  }


  void _outlineBlock(CanvasRenderingContext2D ctx) {
    ctx.beginPath();
    ctx.moveTo(x + BLOCK_PADDING, y);
    _outlineTop(ctx, !hasPrev && hasTopConnector);
    _outlineRight(ctx, indent == 0 && !hasPrev, indent == 0 && !hasNext);
    _outlineBottom(ctx, !hasNext && indent == 0);
    _outlineLeft(ctx);
    ctx.closePath();
  }


//--------------------------------------------------------------
// outline the right side of a block
//--------------------------------------------------------------
  void _outlineRight(CanvasRenderingContext2D ctx, bool curveTop, bool curveBottom) {
    num r = BLOCK_PADDING;
    ctx.lineTo(x + width - r, y);

    if (curveTop && curveBottom) {
      ctx.quadraticCurveTo(x + width, y, x + width, y + r);
      ctx.lineTo(x + width, y + height - r);
      ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
    }
    else if (curveBottom) {
      ctx.lineTo(x + width, y);
      ctx.lineTo(x + width, y + height - r);
      ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
    }
    else if (curveTop) {
      ctx.quadraticCurveTo(x + width, y, x + width, y + r);
      ctx.lineTo(x + width, y + height);
      ctx.lineTo(x + width - r, y + height);
    }
    else {
      ctx.lineTo(x + width, y);
      ctx.lineTo(x + width, y + height);
      ctx.lineTo(x + width - r, y + height);
    }
  }


//--------------------------------------------------------------
// outline the left side of a block
//--------------------------------------------------------------
  void _outlineLeft(CanvasRenderingContext2D ctx) {
    num r = BLOCK_PADDING;

    if (indent > 0 || (hasPrev && hasNext)) {
      ctx.lineTo(x, y + height);
      ctx.lineTo(x, y);
      ctx.lineTo(x + r, y);
    }
    else if (hasNext) {
      ctx.lineTo(x, y + height);
      ctx.lineTo(x, y + r);
      ctx.quadraticCurveTo(x, y, x + r, y);
    }
    else if (hasPrev) {
      ctx.quadraticCurveTo(x, y + height, x, y + height - r);
      ctx.lineTo(x, y);
      ctx.lineTo(x + r, y);
    }
    else {
      ctx.quadraticCurveTo(x, y + height, x, y + height - r);
      ctx.lineTo(x, y + r);
      ctx.quadraticCurveTo(x, y, x + r, y);
    }
  }


//--------------------------------------------------------------
// outline the top of a block
//--------------------------------------------------------------
  void _outlineTop(CanvasRenderingContext2D ctx, bool drawNotch) {
    num r = BLOCK_PADDING;
    num x1 = x + r * 2 + BLOCK_INDENT * indentAbove;

    if (drawNotch) {
      ctx.lineTo(x1, y);
      ctx.bezierCurveTo(x1, y + r/2, 
                        x1 + r, y + r/2, 
                        x1 + r, y);
    }
    ctx.lineTo(x + width - r, y);
  }


//--------------------------------------------------------------
// outline the bottom of a block
//--------------------------------------------------------------
  void _outlineBottom(CanvasRenderingContext2D ctx, bool drawNotch) {
    num r = BLOCK_PADDING;
    num x1 = x + r * 2;
    if (!_inMenu) x1 += BLOCK_INDENT * indentBelow;

    if (drawNotch) {
      ctx.lineTo(x1 + r, y + height);
      ctx.bezierCurveTo(x1 + r, y + height + r/2, 
                        x1, y + height + r/2, 
                        x1, y + height);
    }
    ctx.lineTo(x1 - r, y + height);
  }


  bool containsTouch(Contact c) {
    double tx = c.touchX;
    double ty = c.touchY;
    num y0 = y;
    num y1 = y + height;
    return (tx >= x && ty >= y0 && tx <= x + width && ty <= y1);
  }


  Touchable touchDown(Contact c) {
    _dragging = true;
    _touchX = c.touchX;
    _touchY = c.touchY;
    _lastX = c.touchX;
    _lastY = c.touchY;
    
    // remove block from program
    if (hasPrev) {
      prev.next = null;
      prev = null;
    }

    Block below = this;
    while (below != null) {
      workspace._moveToTop(below);
      below = below.nextChain;
    }
    return this;
  }

  
  void touchUp(Contact c) {
    _dragging = false;
    _inMenu = false;
    _wasInMenu = false;
    if (workspace._trashChain(this)) {
      Sounds.playSound("trash");
    }
    else if (workspace._snapTogether(this)) {
      Sounds.playSound("click");
    }
    workspace.programChanged();
  }


  void touchDrag(Contact c) {
    _touchX = c.touchX;
    _touchY = c.touchY;
  }

  void touchSlide(Contact c) { 
    print("slide");
  }  
}