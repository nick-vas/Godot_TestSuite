using System.Text;
using Breakout.Core.Net;
using Xunit;

namespace Breakout.Core.Tests;

// Join tokens a matchmaker signs and a dedicated server checks in Godot's authentication step (docs/googleforgames.md).
public sealed class JoinTokenTests
{
    static readonly byte[] Key = Encoding.UTF8.GetBytes("a test key of at least thirty-two bytes, never shipped");
    static readonly JoinTokens Tokens = new(Key);
    const long Now = 1_800_000_000;

    static string Token(string server = "eu-1", string player = "p42", long expires = Now + 30, string nonce = "n1") =>
        Tokens.Issue(new JoinClaims(server, player, expires, nonce));

    [Fact]
    public void AValidTokenIsAcceptedOnceOnItsServer()
    {
        var gate = new JoinGate(Tokens, "eu-1");
        Assert.Equal(JoinVerdict.Accepted, gate.Admit(Token(), Now, out var claims));
        Assert.Equal("p42", claims!.PlayerId);
        Assert.Equal(JoinVerdict.Reused, gate.Admit(Token(), Now + 1, out _));   // the same token replayed
        Assert.Equal(JoinVerdict.Accepted, gate.Admit(Token(nonce: "n2"), Now + 1, out _));
    }

    [Fact]
    public void AnotherServersTokenIsRefused()
    {
        var gate = new JoinGate(Tokens, "eu-1");
        Assert.Equal(JoinVerdict.WrongServer, gate.Admit(Token(server: "us-3"), Now, out _));
    }

    [Fact]
    public void ExpiryAllowsAFewSecondsOfClockDifference()
    {
        var gate = new JoinGate(Tokens, "eu-1", skewSeconds: 5);
        Assert.Equal(JoinVerdict.Accepted, gate.Admit(Token(expires: Now - 5, nonce: "a"), Now, out _));
        Assert.Equal(JoinVerdict.Expired, gate.Admit(Token(expires: Now - 6, nonce: "b"), Now, out _));
    }

    [Fact]
    public void AnyChangeBreaksTheSignature()
    {
        string token = Token();
        int dot = token.IndexOf('.');
        // Claim another player by re-encoding the body without the key.
        string forged = Convert.ToBase64String(Encoding.UTF8.GetBytes($"eu-1|admin|{Now + 30}|n1")).TrimEnd('=')
            .Replace('+', '-').Replace('/', '_') + token[dot..];
        Assert.Equal(JoinVerdict.BadSignature, Tokens.Check(forged, out var claims));
        Assert.Null(claims);
        var otherKey = new JoinTokens(Encoding.UTF8.GetBytes("another key that is also thirty-two bytes long"));
        Assert.Equal(JoinVerdict.BadSignature, otherKey.Check(token, out _));
        char last = token[^1] == 'A' ? 'B' : 'A';
        Assert.Equal(JoinVerdict.BadSignature, Tokens.Check(token[..^1] + last, out _));
    }

    [Theory]
    [InlineData("")]
    [InlineData("no-dot")]
    [InlineData("a.b.c")]
    [InlineData(".sig")]
    [InlineData("!!!.???")]
    public void GarbageIsMalformedNotAnException(string token) =>
        Assert.Equal(JoinVerdict.Malformed, Tokens.Check(token, out _));

    [Fact]
    public void ShortKeysAndSeparatorsInIdsAreRefused()
    {
        Assert.Throws<ArgumentException>(() => new JoinTokens(new byte[16]));
        Assert.Throws<ArgumentException>(() => Token(player: "p|admin"));
    }

    [Fact]
    public void RememberedNoncesAreForgottenAfterTheyExpire()
    {
        var gate = new JoinGate(Tokens, "eu-1", skewSeconds: 0);
        Assert.Equal(JoinVerdict.Accepted, gate.Admit(Token(expires: Now + 10, nonce: "x"), Now, out _));
        // Long after, the same token is refused as expired, not as reused: its nonce was dropped, and expiry still holds.
        Assert.Equal(JoinVerdict.Expired, gate.Admit(Token(expires: Now + 10, nonce: "x"), Now + 3600, out _));
    }
}
