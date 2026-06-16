import { useState } from 'react';
import type { Labels } from '@/lib/data';
import { Icon } from './Icon';

export function ResetAuthModal({
  labels,
  onClose,
  onResetSuccess
}: {
  labels: Labels;
  onClose: () => void;
  onResetSuccess: (newToken: string) => void;
}) {
  const [currentToken, setCurrentToken] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleReset = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!currentToken.trim()) {
      setError('Please enter the current token');
      return;
    }
    setLoading(true);
    setError('');

    try {
      const response = await fetch('/auth/reset', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${window.localStorage.getItem('xworkspace-bridge-token') || ''}`,
        },
        body: JSON.stringify({ currentToken }),
      });

      if (!response.ok) {
        const errData = await response.json();
        throw new Error(errData.error || 'Failed to reset token');
      }

      const data = await response.json();
      if (data.token) {
        onResetSuccess(data.token);
      } else {
        throw new Error('No token returned from server');
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred while resetting');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      position: 'fixed',
      top: 0, left: 0, right: 0, bottom: 0,
      backgroundColor: 'rgba(0, 0, 0, 0.5)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      zIndex: 10000,
    }}>
      <div style={{
        backgroundColor: 'var(--card-bg, #fff)',
        color: 'var(--text, #333)',
        borderRadius: '8px',
        padding: '24px',
        width: '400px',
        maxWidth: '90%',
        boxShadow: '0 4px 12px rgba(0,0,0,0.15)'
      }}>
        <h2 style={{ marginTop: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Icon name="terminal" /> Reset Auth Token
        </h2>
        <p style={{ color: '#d32f2f', fontSize: '0.9rem', marginBottom: '16px' }}>
          <strong>Warning:</strong> This will invalidate the current token. All connected services (LiteLLM, OpenClaw, Vault, Hermes) will automatically restart and drop existing connections. You will need the new token to log in.
        </p>
        
        <form onSubmit={handleReset}>
          <div style={{ marginBottom: '16px' }}>
            <label style={{ display: 'block', marginBottom: '8px', fontWeight: 'bold' }}>
              Confirm Current Token
            </label>
            <input
              type="password"
              value={currentToken}
              onChange={(e) => setCurrentToken(e.target.value)}
              placeholder="Paste current token here to confirm..."
              style={{
                width: '100%',
                padding: '8px',
                borderRadius: '4px',
                border: '1px solid var(--border, #ccc)',
                backgroundColor: 'var(--input-bg, #fff)',
                color: 'var(--text, #333)',
                boxSizing: 'border-box'
              }}
              autoFocus
            />
          </div>
          
          {error && <div style={{ color: '#d32f2f', marginBottom: '16px', fontSize: '0.9rem' }}>{error}</div>}
          
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px' }}>
            <button
              type="button"
              onClick={onClose}
              disabled={loading}
              style={{
                padding: '8px 16px',
                borderRadius: '4px',
                border: '1px solid var(--border, #ccc)',
                background: 'transparent',
                cursor: 'pointer',
                color: 'var(--text, #333)'
              }}
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading}
              style={{
                padding: '8px 16px',
                borderRadius: '4px',
                border: 'none',
                background: '#d32f2f',
                color: '#fff',
                cursor: loading ? 'not-allowed' : 'pointer'
              }}
            >
              {loading ? 'Resetting...' : 'Reset Token'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
