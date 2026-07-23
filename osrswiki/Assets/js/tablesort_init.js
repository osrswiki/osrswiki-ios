// Extend Tablesort.js with a custom parser for comma-separated numbers.
Tablesort.extend('numeric-comma', function(item) {
  return /^[−-]?[\d,]+(?:\.\d+)?$/.test(item.trim());
}, function(a, b) {
  var cleanA = a.trim().replace(/,/g, '').replace('−', '-');
  var cleanB = b.trim().replace(/,/g, '').replace('−', '-');
  var numA = parseFloat(cleanA);
  var numB = parseFloat(cleanB);
  numA = isNaN(numA) ? 0 : numA;
  numB = isNaN(numB) ? 0 : numB;
  return numA - numB;
});

// Extend Tablesort.js with a custom parser for intensity values.
Tablesort.extend('intensity', function(item) {
  return /^(low|medium|moderate|high)$/i.test(item.trim());
}, function(a, b) {
  var intensityMap = {
    'low': 0, 'medium': 1, 'moderate': 1, 'high': 2
  };
  var valueA = intensityMap[a.toLowerCase().trim()];
  var valueB = intensityMap[b.toLowerCase().trim()];
  valueA = (valueA === undefined) ? -1 : valueA;
  valueB = (valueB === undefined) ? -1 : valueB;
  return valueA - valueB;
});

// Run DOM manipulations after the page content is loaded.
document.addEventListener('DOMContentLoaded', function() {
  // --- Task 1: Relocate the map into the infobox ---
  var infobox = document.querySelector('.infobox');
  var locationTable = document.querySelector('table.relative-location');

  if (infobox && locationTable) {
    var infoboxBody = infobox.querySelector('tbody');
    var locationHeader = locationTable.querySelector('.relative-location-header');

    if (infoboxBody && locationHeader) {
      let maxCols = 0;
      const rows = infobox.querySelectorAll('tbody > tr');
      rows.forEach(function(row) {
        let currentColCount = 0;
        for (const cell of row.cells) {
          currentColCount += cell.colSpan;
        }
        if (currentColCount > maxCols) {
          maxCols = currentColCount;
        }
      });
      const colspan = maxCols > 0 ? maxCols : 2;

      var headerRow = document.createElement('tr');
      var headerCell = document.createElement('td');
      headerCell.className = 'infobox-header';
      headerCell.colSpan = colspan;
      headerCell.innerHTML = locationHeader.innerHTML;
      headerRow.appendChild(headerCell);

      var contentRow = document.createElement('tr');
      var contentCell = document.createElement('td');
      contentCell.colSpan = colspan;
      contentCell.appendChild(locationTable);
      contentRow.appendChild(contentCell);

      locationTable.removeAttribute('style');
      locationHeader.parentElement.remove();

      infoboxBody.appendChild(headerRow);
      infoboxBody.appendChild(contentRow);
    }
  }

  // --- Task 2: Initialize sorting on any sortable wikitables ---
  var sortableTables = document.querySelectorAll('table.wikitable.sortable');
  sortableTables.forEach(function(table) {
    if (!table.querySelector('thead')) {
      var thead = document.createElement('thead');
      if (table.rows.length > 0) {
        thead.appendChild(table.rows[0]);
      }
      table.insertBefore(thead, table.firstChild);
    }
    new Tablesort(table);
  });
});
