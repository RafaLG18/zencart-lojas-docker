<?php
// Define usuário/senha do admin (admin_id=1) a partir das variáveis de ambiente.
$db = new mysqli('db', getenv('DB_USER'), getenv('DB_PASSWORD'), getenv('DB_DATABASE'));
$user = getenv('ADMIN_USER') ?: 'admin';
$email = "$user@localhost";
$hash = password_hash(getenv('ADMIN_PASSWORD'), PASSWORD_DEFAULT);
$st = $db->prepare('UPDATE admin SET admin_name = ?, admin_email = ?, admin_pass = ?, pwd_last_change_date = NOW() WHERE admin_id = 1');
$st->bind_param('sss', $user, $email, $hash);
$st->execute();
echo "[zencart] admin '$user' configurado\n";
