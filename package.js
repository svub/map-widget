Package.describe({
  summary: "Leaflet map packed as widget for Meteor."
});

Package.on_use(function (api, where) {
  if(api.export) { api.export('mapWidget'); }
  
  api.use(['less', 'coffeescript', 'bootstrap3-less', 'underscore', 'meteor', 'templating', 'ejson', 'deps', 'tools'], 'client');  

  api.add_files('client/map.widget.html', 'client');
  api.add_files('client/map.widget.less', 'client');
  api.add_files('client/map.widget.coffee', 'client');

});
