<?php

declare(strict_types=1);

require __DIR__ . '/../vendor/autoload.php';

use GuzzleHttp\Client;
use Monolog\Handler\StreamHandler;
use Monolog\Logger;
use Twig\Environment;
use Twig\Loader\ArrayLoader;

// --- Logging (Monolog) : les logs partent sur stderr, captés par Docker. ---
$log = new Logger('api');
$log->pushHandler(new StreamHandler('php://stderr', Logger::INFO));

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$log->info('Requête entrante', ['path' => $path]);

// --- Routage minimaliste (pas de framework : le focus du lab est l'image). ---
switch ($path) {
    case '/':
        // Page de statut rendue avec Twig (moteur de templates).
        $twig = new Environment(new ArrayLoader([
            'status' => "<h1>{{ name }}</h1>\n<p>version {{ version }} — statut : OK</p>\n",
        ]));
        header('Content-Type: text/html; charset=utf-8');
        echo $twig->render('status', ['name' => 'Secure API', 'version' => '1.0.0']);
        break;

    case '/health':
        header('Content-Type: application/json');
        echo json_encode(['status' => 'ok', 'version' => '1.0.0']);
        break;

    case '/subscribers':
        $log->info('Listing subscribers');
        header('Content-Type: application/json');
        echo json_encode([
            ['id' => 1, 'name' => 'Jean Dupont', 'email' => 'jean.dupont@example.com'],
            ['id' => 2, 'name' => 'Marie Martin', 'email' => 'marie.martin@example.com'],
        ]);
        break;

    case '/upstream-status':
        // Health-check d'un service amont via Guzzle. Tolérant aux pannes :
        // hors-ligne, on renvoie un statut dégradé plutôt que de planter.
        $upstream = getenv('UPSTREAM_URL') ?: 'https://example.com';
        $client = new Client(['timeout' => 2.0]);
        try {
            $code = $client->get($upstream)->getStatusCode();
            $reachable = true;
        } catch (\Throwable $e) {
            $log->warning('Upstream injoignable', ['error' => $e->getMessage()]);
            $code = null;
            $reachable = false;
        }
        header('Content-Type: application/json');
        echo json_encode(['upstream' => $upstream, 'reachable' => $reachable, 'code' => $code]);
        break;

    default:
        http_response_code(404);
        header('Content-Type: application/json');
        echo json_encode(['error' => 'Not found', 'path' => $path]);
}
