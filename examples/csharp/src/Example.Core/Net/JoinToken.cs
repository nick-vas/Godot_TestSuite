using System.Security.Cryptography;
using System.Text;

namespace Example.Core.Net;

/// <summary>What a join token says: who may join which server, until when. <see cref="Nonce"/> makes each token single-use.</summary>
public sealed record JoinClaims(string ServerId, string PlayerId, long ExpiresUnix, string Nonce);

public enum JoinVerdict { Accepted, Malformed, BadSignature, Expired, WrongServer, Reused }

/// <summary>
/// A join token: the matchmaker (or lobby service) that picked the server signs who may join it, the client hands the
/// token over in Godot's authentication step (<c>SceneMultiplayer.AuthCallback</c>, <c>SendAuth</c>,
/// <c>CompleteAuth</c>), and the server lets in only peers with a valid one. Open Match hands the client a server address
/// as its assignment and Quilkin routes only packets that carry a known token; this is the same idea for a server you
/// run yourself, without either. HMAC-SHA256 with a secret the matchmaker and the servers share; never ship the secret
/// in the client.
/// Format: base64url(serverId|playerId|expires|nonce) "." base64url(HMAC of the first part). Ids must not contain '|'.
/// </summary>
public sealed class JoinTokens
{
    readonly byte[] _key;

    public JoinTokens(byte[] key)
    {
        if (key.Length < 32) throw new ArgumentException("use a key of at least 32 random bytes", nameof(key));
        _key = key;
    }

    public string Issue(JoinClaims claims)
    {
        foreach (var part in new[] { claims.ServerId, claims.PlayerId, claims.Nonce })
            if (part.Contains('|')) throw new ArgumentException($"'{part}' contains '|'", nameof(claims));
        var body = Encoding.UTF8.GetBytes($"{claims.ServerId}|{claims.PlayerId}|{claims.ExpiresUnix}|{claims.Nonce}");
        return $"{Base64Url(body)}.{Base64Url(HMACSHA256.HashData(_key, body))}";
    }

    /// <summary>Checks the signature first, then the claims; nothing in an unsigned token is trusted or parsed further.</summary>
    public JoinVerdict Check(string token, out JoinClaims? claims)
    {
        claims = null;
        int dot = token.IndexOf('.');
        if (dot <= 0 || dot != token.LastIndexOf('.')) return JoinVerdict.Malformed;
        byte[] body, signature;
        try
        {
            body = FromBase64Url(token[..dot]);
            signature = FromBase64Url(token[(dot + 1)..]);
        }
        catch (FormatException) { return JoinVerdict.Malformed; }
        // Constant time: comparing byte by byte and stopping at the first difference leaks how much of a guess was right.
        if (!CryptographicOperations.FixedTimeEquals(signature, HMACSHA256.HashData(_key, body))) return JoinVerdict.BadSignature;
        var parts = Encoding.UTF8.GetString(body).Split('|');
        if (parts.Length != 4 || !long.TryParse(parts[2], out long expires)) return JoinVerdict.Malformed;
        claims = new JoinClaims(parts[0], parts[1], expires, parts[3]);
        return JoinVerdict.Accepted;
    }

    static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    static byte[] FromBase64Url(string text)
    {
        string s = text.Replace('-', '+').Replace('_', '/');
        return Convert.FromBase64String(s.PadRight(s.Length + (4 - s.Length % 4) % 4, '='));
    }
}

/// <summary>
/// The server's side: one per game server process. Accepts a token once, for this server, before it expires (with a
/// little slack for clocks that differ). Remembered nonces are dropped once their token has expired anyway.
/// </summary>
public sealed class JoinGate(JoinTokens tokens, string serverId, long skewSeconds = 5)
{
    readonly Dictionary<string, long> _used = new();

    public JoinVerdict Admit(string token, long nowUnix, out JoinClaims? claims)
    {
        var verdict = tokens.Check(token, out claims);
        if (verdict != JoinVerdict.Accepted) return verdict;
        if (claims!.ServerId != serverId) return JoinVerdict.WrongServer;
        if (nowUnix > claims.ExpiresUnix + skewSeconds) return JoinVerdict.Expired;
        foreach (var stale in _used.Where(u => u.Value + skewSeconds < nowUnix).Select(u => u.Key).ToList()) _used.Remove(stale);
        if (!_used.TryAdd(claims.Nonce, claims.ExpiresUnix)) return JoinVerdict.Reused;
        return JoinVerdict.Accepted;
    }
}
