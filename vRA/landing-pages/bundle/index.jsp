<!DOCTYPE HTML>
<html>

   <head>
      <title>EPFL Infrastructure As A Service</title>
      <link type="text/css" rel="stylesheet" href="iaas.css">
      <meta charset="UTF-8">
   </head>
   
   <body>
      <h1><img src="images/logo-EPFL-2019-red.png"> Infrastructure as a Service</h1>
      <div class="all-tenants">
         
         <a href="/vcac/org/epfl/">
            <div class="tenant tenant-epfl">
               <img src="images/logo-EPFL-2019-white.png" class="logo" />
               <h2 id="epfl"><!--content set using JS --></h2>
            </div>
         </a>
         
         <a href="/vcac/org/itservices/">
            <div class="tenant tenant-its">
               <img src="images/logo-ITServices.png" class="logo" /><br>
               <h2 id="its"><!--content set using JS --></h2>
            </div>
         </a>

         <a href="/vcac/org/research/">
            <div class="tenant tenant-research">
               <img src="images/logo-Research.png" class="logo" /><br>
               <h2 id="research"><!--content set using JS --></h2>
            </div>
         </a>
      </div>
      
   </body>
   
   
   <script>
      var userLang = navigator.language || navigator.userLanguage; 
      document.getElementById('its').innerHTML = (userLang.startsWith("fr"))?"Portail Services IT":"IT Service Portal";   
      document.getElementById('epfl').innerHTML = (userLang.startsWith("fr"))?"Portail Unit&eacute;s EPFL":"EPFL Units Portal";   
      document.getElementById('research').innerHTML = (userLang.startsWith("fr"))?"Portail Recherche":"Research Portal";   
   </script>

</html>