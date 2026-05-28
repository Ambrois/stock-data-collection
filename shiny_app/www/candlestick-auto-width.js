/**
 * The Candle chart plotter is adapted from code written by
 * Zhenlei Cai (jpenguin@gmail.com)
 * https://github.com/danvk/dygraphs/pull/141/files
 */

(function() {
  "use strict";

  function getPrices(sets) {
    var prices = [];
    var price;
    for (var p = 0 ; p < sets[0].length; p++) {
      price = {
        open : sets[0][p].yval,
        high : sets[1][p].yval,
        low : sets[2][p].yval,
        close : sets[3][p].yval,
        openY : sets[0][p].y,
        highY : sets[1][p].y,
        lowY : sets[2][p].y,
        closeY : sets[3][p].y
      };
      prices.push(price);
    }
    return prices;
  }

  function getPointX(point, area) {
    if (typeof point.canvasx === 'number' && isFinite(point.canvasx)) {
      return point.canvasx;
    }

    return area.x + point.x * area.w;
  }

  function getAutoBarWidth(points, area) {
    var previousX = null;
    var minSpacing = Infinity;

    for (var p = 0; p < points.length; p++) {
      var currentX = getPointX(points[p], area);

      if (previousX !== null) {
        var spacing = currentX - previousX;

        if (spacing > 0 && spacing < minSpacing) {
          minSpacing = spacing;
        }
      }

      previousX = currentX;
    }

    if (!isFinite(minSpacing)) {
      return Math.max(1, Math.floor(Math.min(area.w / 10, 8)));
    }

    var barWidth = Math.floor(minSpacing * 0.75);
    barWidth = Math.min(barWidth, Math.floor(minSpacing));
    barWidth = Math.max(barWidth, minSpacing >= 1 ? 1 : minSpacing);

    if (barWidth > 2 && barWidth % 2 !== 0) {
      barWidth--;
    }

    return barWidth;
  }

  function candlestickPlotter(e) {
    if (e.seriesIndex > 3) {
      Dygraph.Plotters.linePlotter(e);
      return;
    }
    // This is the officially endorsed way to plot all the series at once.
    if (e.seriesIndex !== 0) return;

    var sets = e.allSeriesPoints.slice(0, 4); // Slice first four sets for candlestick chart
    var prices = getPrices(sets);
    var area = e.plotArea;
    var ctx = e.drawingContext;
    ctx.strokeStyle = '#202020';
    ctx.lineWidth = 0.6;

    var barWidth = getAutoBarWidth(sets[0], area);

    var price;
    for (var p = 0 ; p < prices.length; p++) {
      ctx.beginPath();

      price = prices[p];
      var topY = area.h * price.highY + area.y;
      var bottomY = area.h * price.lowY + area.y;
      var centerX = Math.floor(getPointX(sets[0][p], area)) + 0.5; // crisper rendering
      ctx.moveTo(centerX, topY);
      ctx.lineTo(centerX, bottomY);
      ctx.closePath();
      ctx.stroke();
      var bodyY;
      if (price.open > price.close) {
        ctx.fillStyle ='#d9534f';
        bodyY = area.h * price.openY + area.y;
      }
      else {
        ctx.fillStyle ='#5cb85c';
        bodyY = area.h * price.closeY  + area.y;
      }
      var bodyHeight = area.h * Math.abs(price.openY - price.closeY);
      ctx.fillRect(centerX - barWidth / 2, bodyY, barWidth,  bodyHeight);
    }
  };
  candlestickPlotter._getPrices = getPrices; // for testing
  candlestickPlotter._getAutoBarWidth = getAutoBarWidth; // for testing
  Dygraph.Plotters.AutoWidthCandlestickPlotter = candlestickPlotter;
})();
