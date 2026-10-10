<?php
// Gera os configure.php (loja e admin) a partir dos templates do instalador.
// Uso no build: php zc-configure.php <raiz> <pasta-do-admin>
[, $root, $adminDir] = $argv;
$tplDir = "$root/zc_install/includes";

// Valores entre aspas no template são trocados por expressões PHP lidas do ambiente
$url = "(getenv('ZC_URL') ?: 'http://' . (\$_SERVER['HTTP_HOST'] ?? 'localhost'))";
$code = [
    'CATALOG_HTTP_SERVER' => $url,
    'CATALOG_HTTPS_SERVER' => $url,
    'HTTP_SERVER_ADMIN' => $url,
    'DB_SERVER_USERNAME' => "getenv('DB_USER')",
    'DB_SERVER_PASSWORD' => "getenv('DB_PASSWORD')",
    'DB_DATABASE' => "getenv('DB_DATABASE')",
];
$literal = [
    'INSTALLER_METHOD' => 'zc-configure.php (Docker)',
    'DATE_NOW' => date('D M d Y H:i:s'),
    'ENABLE_SSL_CATALOG' => 'false',
    'DIR_WS_CATALOG' => '/',
    'DIR_WS_HTTPS_CATALOG' => '/',
    'DIR_FS_CATALOG' => "$root/",
    'DB_TYPE' => 'mysql',
    'DB_PREFIX' => '',
    'DB_CHARSET' => 'utf8mb4',
    'DB_SERVER' => 'db',
    'SQL_CACHE_METHOD' => 'none',
    'SESSION_STORAGE' => 'reserved for future use',
];

$targets = [
    'catalog-configure-template.php' => "$root/includes/configure.php",
    'admin-configure-template.php' => "$root/$adminDir/includes/configure.php",
];
foreach ($targets as $tpl => $out) {
    $text = file_get_contents("$tplDir/$tpl");
    foreach ($code as $k => $v) {
        $text = str_replace("'%%_{$k}_%%'", $v, $text);
    }
    foreach ($literal as $k => $v) {
        $text = str_replace("%%_{$k}_%%", $v, $text);
    }
    if (str_contains($text, '%%_')) {
        fwrite(STDERR, "placeholder não substituído em $tpl\n");
        exit(1);
    }
    file_put_contents($out, $text);
    echo "gerado $out\n";
}
