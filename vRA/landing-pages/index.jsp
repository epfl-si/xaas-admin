<!DOCTYPE HTML>
<html>

   <head>
      <title>EPFL Infrastructure As A Service</title>
      <link type="text/css" rel="stylesheet" href="iaas.css">
      <meta charset="UTF-8">
   </head>
   
   <body>
      <h1><img src="images/logo-EPFL.jpg"> Infrastructure as a Service</h1>
      <div class="all-tenants only-one-tenant">
         
         <a href="/vcac/org/itservices/">
            <div class="tenant tenant-its">
               <img src="images/logo-ITServices.png" class="logo" /><br>
               <h2 id="its"><!--content set using JS --></h2>
            </div>
         </a>
      </div>
      
   </body>
   
   
   <script>
      var userLang = navigator.language || navigator.userLanguage; 
      document.getElementById('its').innerHTML = (userLang.startsWith("fr"))?"Portail Services IT":"IT Service Portal";   
   </script>

</html>